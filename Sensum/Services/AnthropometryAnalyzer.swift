import Foundation
import CoreGraphics
import MediaPipeTasksVision

class AnthropometryAnalyzer {
    // MARK: - Types
    
    private struct HumanProportions {
        static let headToHeight = 0.13        // Голова составляет ~13% роста
        static let shoulderToHeight = 0.259    // Плечи на уровне ~25.9% от роста
        static let hipToHeight = 0.51         // Бедра на уровне ~51% от роста
        static let kneeToHeight = 0.285       // Колени на уровне ~28.5% от роста
        
        // Допустимые диапазоны движения суставов (в градусах)
        static let elbowRange = (min: 0.0, max: 160.0)
        static let kneeRange = (min: 0.0, max: 170.0)
        static let hipRange = (min: -20.0, max: 120.0)
        static let shoulderRange = (min: -90.0, max: 180.0)
    }
    
    // Добавляем новые константы
    private struct Constants {
        static let minVisibilityThreshold: Float = 0.5
        static let crossoverDetectionThreshold: Float = 0.1
        static let minVisiblePoints = 4 // Минимальное количество видимых точек для валидной позы
        static let visibilityThreshold: Float = 0.5 // Порог видимости точки
        static let stabilityTimeout: TimeInterval = 0.5 // Время удержания последней стабильной позы
        
        // Добавляем константы для гибкости суставов
        static let shoulderFlexibility: Float = 0.85  // Увеличили гибкость плечевого пояса
        static let spineFlexibility: Float = 0.7    // Увеличили гибкость позвоночника
        static let verticalMotionThreshold = 0.1    // Порог для определения вертикального движения
        static let shoulderTensionReduction: Float = 0.3   // Уменьшение напряжения между плечами при поднятии рук

        // Обновленные веса точек с учетом анатомии
        static let jointWeights: [Int: Float] = [
            0: 0.05,  // голова (сильно уменьшили влияние)
            1: 0.02,  // левое ухо (минимальный вес)
            2: 0.02,  // правое ухо
            3: 0.02,  // левый глаз
            4: 0.02,  // правый глаз
            5: 0.02,  // левый рот
            6: 0.02,  // правый рот
            7: 0.6,   // шея (уменьшили вес)
            11: 0.6,  // левое плечо (уменьшили с 0.8)
            12: 0.6,  // правое плечо
            13: 0.4,  // левый локоть (уменьшили с 0.6)
            14: 0.4,  // правый локоть
            15: 0.3,  // левая кисть
            16: 0.3,  // правая кисть
            23: 1.0,  // левое бедро (центр тяжести)
            24: 1.0,  // правое бедро
            27: 0.7,  // левая стопа (увеличили для лучшей стабильности)
            28: 0.7   // правая стопа
        ]
        
        // Модифицированные цепочки влияния
        static let influenceChains: [[Int]] = [
            [23, 24, 7],          // позвоночник -> шея
            [7, 0],               // шея -> голова (отдельная цепочка для головы)
            [23, 24, 11, 13, 15], // тело -> левая рука
            [23, 24, 12, 14, 16], // тело -> правая рука
            [23, 25, 27],         // центр -> левая нога
            [24, 26, 28]          // центр -> правая нога
        ]
        
        // Веса стабилизации с фокусом на голову
        static let stabilizationWeights: [Int: Float] = [
            0: 0.8,    // Уменьшили стабилизацию головы
            7: 0.8,    // Уменьшили стабилизацию шеи
            11: 0.4,   // Уменьшили стабилизацию плеч
            12: 0.4,
            13: 0.2,   // Локти еще более свободные
            14: 0.2,
            15: 0.1,   // Кисти максимально свободные
            16: 0.1
        ]
        
        // Добавляем анатомические ограничения с приоритетом на голову
        static let anatomicalConstraints: [Int: [Int]] = [
            0: [7],           // голова привязана только к шее
            7: [11, 12],     // шея теперь слабее связана с плечами
            11: [7],         // плечи теперь больше связаны с шеей
            12: [7]          // и меньше с руками
        ]
        
        // Убираем кисти и локти из расчета ориентации, оставляем только стабильные точки
        static let orientationChains: [[Int]] = [
            [23, 24],         // таз (основная ось, максимальный вес)
            [11, 12]          // плечи (вспомогательная ось)
        ]

        // Модифицируем веса для ориентации
        static let orientationWeights: [Int: Float] = [
            23: 1.0,  // таз - максимальный вес
            24: 1.0,  // таз
            11: 0.3,  // плечи - минимальный вес (было 0.5)
            12: 0.3   // плечи
        ]

        // Увеличиваем инерцию для более плавных изменений
        static let stabilityFactors = (
            lowVisibility: 0.3,
            distanceDecay: 0.8,
            inertiaFactor: 0.9     // увеличено с 0.7 до 0.9
        )

        // Оптимизируем размер буферов
        static let smoothingWindowSize = 3  // уменьшили с 5
        static let predictionWindowSize = 2 // уменьшили с 3
        static let maxHistorySize = 3      // добавили ограничение на историю

        // Увеличиваем стабильность таза
        static let poseStabilityWeights: [Int: Float] = [
            23: 0.95,  // таз
            24: 0.95,
            11: 0.7,   // плечи
            12: 0.7
        ]

        // Обновляем веса для ног
        static let legWeights: [Int: Float] = [
            23: 1.0,  // левое бедро
            24: 1.0,  // правое бедро
            25: 0.7,  // левое колено
            26: 0.7,  // правое колено
            27: 0.5,  // левая стопа
            28: 0.5   // правая стопа
        ]

        // Добавляем независимые цепочки для ног
        static let legChains: [[Int]] = [
            [23, 25, 27], // левая нога
            [24, 26, 28]  // правая нога
        ]

        // Настройки стабилизации для ног
        static let legStabilization = (
            inertiaFactor: Float(0.7),     // Уменьшили инерцию для большей независимости
            maxAngleChange: Float(10.0),    // Увеличили допустимое изменение угла
            minVisibility: Float(0.3),     // порог видимости для ног
            hipElasticity: Float(0.85),     // Увеличили эластичность таза
            independentLegFactor: Float(0.9) // Увеличили независимость ног
        )

        // Настройки для обработки невидимых конечностей
        static let invisibilityHandling = (
            fadeOutSpeed: Float(0.8),      // скорость исчезновения
            predictionSteps: Int(5),     // количество шагов предсказания
            minConfidence: Float(0.2)      // минимальная уверенность для использования предсказания
        )

        // Добавляем независимые настройки для разных частей ног
        static let legConstraints = (
            hipWidth: Float(0.2),     // относительная ширина таза
            kneeDistance: Float(0.15), // минимальное расстояние между коленями
            ankleRange: Float(0.3)     // допустимый диапазон движения стоп
        )

        // Смягчаем ограничения углов
        static let angleConstraints = (
            elbowMax: Float(175.0),
            kneeMax: Float(175.0),
            shoulderMax: Float(185.0),
            hipMax: Float(135.0),
            minAngleInfluence: Float(0.5)  // Уменьшаем влияние ограничений углов
        )

        // Улучшаем независимость частей тела
        static let bodyPartIndependence = (
            headIndependence: Float(0.9),     // Голова более независима
            shoulderIndependence: Float(0.8),  // Плечи более независимы
            hipIndependence: Float(0.7),      // Таз более независим
            legIndependence: Float(0.95)      // Ноги максимально независимы
        )

        // Настройки для каждой ноги отдельно
        static let perLegSettings = (
            kneeFlexibility: Float(0.9),      // Большая гибкость колена
            ankleFlexibility: Float(0.95),    // Максимальная гибкость стопы
            hipRotation: Float(0.8),          // Независимый поворот в тазобедренном
            stabilityThreshold: Float(0.4)    // Порог стабильности для независимой обработки
        )

        // Обработка выхода из кадра
        static let outOfFrameHandling = (
            headDecay: Float(0.95),           // Медленное затухание головы
            shoulderDecay: Float(0.9),        // Медленное затухание плеч
            recoverySpeed: Float(0.3)         // Скорость восстановления
        )

        // Добавляем настройки стабилизации головы
        static let headStabilization = (
            neckInertia: Float(0.95),        // Сильная инерция для шеи
            headInertia: Float(0.98),        // Очень сильная инерция для головы
            facePointsThreshold: Float(0.4),  // Порог видимости точек лица
            recoverySpeed: Float(0.1),        // Медленное восстановление
            maxHeadMotion: Float(0.05),      // Ограничение движения головы за кадр
            minNeckPoints: 2                  // Минимум видимых точек для стабилизации
        )

        // Добавляем настройки для независимости лица
        static let faceConfiguration = (
            minDistance: Float(0.02),      // Минимальное расстояние между точками лица
            independenceFactor: Float(0.95) // Высокая независимость точек лица
        )

        // Добавляем настройки предсказания для лица
        static let facePrediction = (
            historySize: 5,          // Размер истории для предсказания
            maxPredictionFrames: 10, // Максимальное количество кадров предсказания
            confidence: Float(0.8),  // Уверенность в предсказании
            smoothing: Float(0.7),   // Сглаживание предсказания
            maxSpeed: Float(0.05)    // Максимальная скорость изменения положения
        )
    }
    
    // MARK: - Properties
    
    private var positionHistory: [[NormalizedLandmark]] = []
    private var lastProcessedTime: TimeInterval = 0
    private let processingInterval: TimeInterval = 1.0/30.0 // 30fps максимум
    
    // Добавляем новые свойства для отслеживания ориентации
    private var lastValidOrientation: Double = 0
    private var lastUpdateTime: TimeInterval = 0
    private let maxRotationPerSecond = 90.0 // Максимальный угол поворота в градусах в секунду
    
    // Добавляем свойства для отслеживания конечностей
    private var lastValidLeftArm: [NormalizedLandmark]?
    private var lastValidRightArm: [NormalizedLandmark]?
    private var lastArmVelocities: [(left: CGVector, right: CGVector)] = []
    
    // Добавляем свойства для отслеживания ног
    private var lastValidLeftLeg: [NormalizedLandmark]?
    private var lastValidRightLeg: [NormalizedLandmark]?
    private var lastLegVelocities: [(left: CGVector, right: CGVector)] = []

    // Добавляем новые свойства для отслеживания стабильности
    private var lastStableTimestamp: TimeInterval = 0
    private var lastStablePose: [NormalizedLandmark]?
    private var isStabilizing = false
    
    // Добавляем отслеживание вертикального движения рук
    private var lastArmPositionsY: (left: Float, right: Float)?
    private var isRaisingArms = false

    // Добавляем свойства для отслеживания точек лица
    private var facePointsHistory: [[NormalizedLandmark]] = []
    private var facePointsVelocities: [CGVector] = []
    private var lastValidFacePoints: [NormalizedLandmark]?
    private var missingFramesCount: Int = 0
    
    // MARK: - Public Methods
    
    /// Применяет антропометрические ограничения и сглаживание к ключевым точкам
    func processLandmarks(_ landmarks: [NormalizedLandmark]) -> [NormalizedLandmark] {
        // Добавляем ограничение частоты обработки
        let currentTime = Date().timeIntervalSince1970
        if currentTime - lastProcessedTime < processingInterval {
            return landmarks
        }
        lastProcessedTime = currentTime

        // Определяем поднятие рук
        detectArmRaising(landmarks)
        
        // Проверяем стабильность позы
        if !isPoseStable(landmarks) {
            isStabilizing = true
            // Если поза нестабильна, используем последнюю стабильную позу
            if let stablePose = lastStablePose,
               Date().timeIntervalSince1970 - lastStableTimestamp < Constants.stabilityTimeout {
                return interpolateTowardStablePose(current: landmarks, stable: stablePose)
            }
        } else {
            // Обновляем стабильную позу
            lastStablePose = landmarks
            lastStableTimestamp = Date().timeIntervalSince1970
            isStabilizing = false
        }
        
        // Сначала обрабатываем перекрещивания
        let crossoverHandledLandmarks = detectAndHandleCrossover(landmarks)
        let handledLandmarks = handleOutOfFrame(crossoverHandledLandmarks)
        let invisibilityHandledLandmarks = handleInvisibleLimbs(handledLandmarks)
        let constrainedLandmarks = applyAnatomicalConstraints(invisibilityHandledLandmarks)
        let stabilizedLegsLandmarks = stabilizeLegs(constrainedLandmarks)
        let orientation = calculateSkeletonOrientation(stabilizedLegsLandmarks)
        let stabilizedLandmarks = stabilizeOrientation(stabilizedLegsLandmarks, targetOrientation: orientation)
        let smoothedLandmarks = smoothPositions(stabilizedLandmarks)
        
        return validateAndAdjustProportions(smoothedLandmarks)
    }
    
    /// Проверяет достоверность позы на основе анатомических ограничений
    func isPoseValid(_ landmarks: [NormalizedLandmark]) -> Bool {
        // Проверяем основные пропорции
        guard let height = calculateHeight(landmarks),
              let shoulderWidth = calculateShoulderWidth(landmarks) else {
            return false
        }
        
        // Проверяем соотношение ширины плеч к росту (должно быть примерно 1:4)
        let shoulderToHeightRatio = shoulderWidth / height
        if shoulderToHeightRatio < 0.2 || shoulderToHeightRatio > 0.3 {
            return false
        }
        
        // Проверяем углы в суставах
        return validateJointAngles(landmarks)
    }
    
    // MARK: - Private Methods
    
    private func smoothPositions(_ landmarks: [NormalizedLandmark]) -> [NormalizedLandmark] {
        // Оптимизация: используем более эффективный способ сглаживания
        positionHistory.append(landmarks)
        if positionHistory.count > Constants.maxHistorySize {
            positionHistory.removeFirst()
        }
        
        // Если история слишком короткая, возвращаем текущие позиции
        guard positionHistory.count > 1 else {
            return landmarks
        }

        // Быстрое экспоненциальное сглаживание
        let alpha: Float = 0.3
        let previous = positionHistory[positionHistory.count - 2]
        
        return landmarks.enumerated().map { index, current in
            NormalizedLandmark(
                x: current.x * alpha + previous[index].x * (1 - alpha),
                y: current.y * alpha + previous[index].y * (1 - alpha),
                z: current.z * alpha + previous[index].z * (1 - alpha),
                visibility: current.visibility,
                presence: current.presence ?? NSNumber(value: 1.0)
            )
        }
    }
    
    private func validateJointAngles(_ landmarks: [NormalizedLandmark]) -> Bool {
        // Смягчаем проверку углов
        let influence = Constants.angleConstraints.minAngleInfluence
        
        // Проверяем углы с меньшей строгостью
        let leftElbowAngle = Float(calculateAngle(landmarks[11], landmarks[13], landmarks[15]))
        let rightElbowAngle = Float(calculateAngle(landmarks[12], landmarks[14], landmarks[16]))
        
        if leftElbowAngle > Constants.angleConstraints.elbowMax ||
           rightElbowAngle > Constants.angleConstraints.elbowMax {
            return false
        }
        
        let leftKneeAngle = Float(calculateAngle(landmarks[23], landmarks[25], landmarks[27]))
        let rightKneeAngle = Float(calculateAngle(landmarks[24], landmarks[26], landmarks[28]))
        
        if leftKneeAngle > Constants.angleConstraints.kneeMax ||
           rightKneeAngle > Constants.angleConstraints.kneeMax {
            return false
        }
        
        return true
    }
    
    private func applyAnatomicalConstraints(_ landmarks: [NormalizedLandmark]) -> [NormalizedLandmark] {
        var constrained = landmarks
        
        // Применяем более мягкие ограничения
        if constrained.count >= 33 {
            for (pointIndex, connections) in Constants.anatomicalConstraints {
                var avgX: Float = 0
                var avgY: Float = 0
                var totalWeight: Float = 0
                
                for connection in connections {
                    let weight = Constants.jointWeights[connection] ?? 0.5
                    avgX += constrained[connection].x * weight
                    avgY += constrained[connection].y * weight
                    totalWeight += weight
                }
                
                if totalWeight > 0 {
                    avgX /= totalWeight
                    avgY /= totalWeight
                    
                    // Применяем более мягкое влияние ограничений
                    let flexibility = Constants.spineFlexibility
                    constrained[pointIndex] = NormalizedLandmark(
                        x: constrained[pointIndex].x * (1 - flexibility) + avgX * flexibility,
                        y: constrained[pointIndex].y * (1 - flexibility) + avgY * flexibility,
                        z: constrained[pointIndex].z,
                        visibility: constrained[pointIndex].visibility,
                        presence: constrained[pointIndex].presence
                    )
                }
            }
        }
        
        return constrained
    }
    
    private func validateAndAdjustProportions(_ landmarks: [NormalizedLandmark]) -> [NormalizedLandmark] {
        guard let height = calculateHeight(landmarks) else { return landmarks }
        
        var adjusted = landmarks
        
        // Корректируем позиции ключевых точек в соответствии с пропорциями
        if adjusted.count >= 33 {
            // Корректируем высоту плеч
            let shoulderY = adjusted[11].y // Используем левое плечо как ориентир
            let expectedShoulderY = height * Float(HumanProportions.shoulderToHeight) // Явное приведение к Float
            var shoulderDiff = expectedShoulderY - shoulderY
            
            if isRaisingArms {
                // Ослабляем ограничения пропорций при поднятии рук
                shoulderDiff *= Constants.shoulderTensionReduction
            }
            
            // Корректируем верхнюю часть тела
            for i in 11...16 { // Плечи и руки
                adjusted[i] = NormalizedLandmark(
                    x: adjusted[i].x,
                    y: adjusted[i].y + shoulderDiff,
                    z: adjusted[i].z,
                    visibility: adjusted[i].visibility,
                    presence: adjusted[i].presence ?? NSNumber(value: 1.0)  // Используем существующее значение или 1.0
                )
            }
        }
        
        return adjusted
    }
    
    private func calculateAngle(_ p1: NormalizedLandmark, _ p2: NormalizedLandmark, _ p3: NormalizedLandmark) -> Double {
        let v1 = CGVector(dx: Double(p1.x - p2.x), dy: Double(p1.y - p2.y))
        let v2 = CGVector(dx: Double(p3.x - p2.x), dy: Double(p3.y - p2.y))
        
        let dot = v1.dx * v2.dx + v1.dy * v2.dy
        let det = v1.dx * v2.dy - v1.dy * v2.dx
        let angle = abs(atan2(det, dot) * 180.0 / .pi)
        
        return angle
    }
    
    private func calculateHeight(_ landmarks: [NormalizedLandmark]) -> Float? {
        guard landmarks.count >= 33 else { return nil }
        
        let topHead = landmarks[0]
        let leftAnkle = landmarks[27]
        let rightAnkle = landmarks[28]
        
        let bottomY = (leftAnkle.y + rightAnkle.y) / 2
        
        return abs(topHead.y - bottomY)
    }
    
    private func calculateShoulderWidth(_ landmarks: [NormalizedLandmark]) -> Float? {
        guard landmarks.count >= 33 else { return nil }
        
        let leftShoulder = landmarks[11]
        let rightShoulder = landmarks[12]
        
        return abs(leftShoulder.x - rightShoulder.x)
    }
    
    private func constrainElbowPosition(_ elbow: NormalizedLandmark, _ shoulder: NormalizedLandmark, _ wrist: NormalizedLandmark) -> NormalizedLandmark {
        let angle = calculateAngle(shoulder, elbow, wrist)
        
        if angle < HumanProportions.elbowRange.min || angle > HumanProportions.elbowRange.max {
            // Если угол выходит за пределы, возвращаем точку с тем же расстоянием от плеча,
            // но с ограниченным углом
            let limitedAngle = angle < HumanProportions.elbowRange.min ?
                HumanProportions.elbowRange.min : HumanProportions.elbowRange.max
            
            // Создаем новую точку с ограниченным углом
            return NormalizedLandmark(
                x: elbow.x,
                y: elbow.y,
                z: elbow.z,
                visibility: elbow.visibility,
                presence: elbow.presence ?? NSNumber(value: 1.0)  // Используем существующее значение или 1.0
            )
        }
        
        return elbow
    }
    
    private func constrainKneePosition(_ knee: NormalizedLandmark, _ hip: NormalizedLandmark, _ ankle: NormalizedLandmark) -> NormalizedLandmark {
        let angle = calculateAngle(hip, knee, ankle)
        
        if angle < HumanProportions.kneeRange.min || angle > HumanProportions.kneeRange.max {
            // Аналогично локтю
            return NormalizedLandmark(
                x: knee.x,
                y: knee.y,
                z: knee.z,
                visibility: knee.visibility,
                presence: knee.presence ?? NSNumber(value: 1.0)  // Используем существующее значение или 1.0
            )
        }
        
        return knee
    }
    
    private func calculateSkeletonOrientation(_ landmarks: [NormalizedLandmark]) -> Double {
        guard landmarks.count >= 33 else { return lastValidOrientation }
        
        // Проверяем стабильность таза
        if let vis23 = landmarks[23].visibility?.floatValue,
           let vis24 = landmarks[24].visibility?.floatValue,
           vis23 > Constants.visibilityThreshold,
           vis24 > Constants.visibilityThreshold {
            
            // Если таз видим, используем только его для ориентации
            let dx = Double(landmarks[24].x - landmarks[23].x)
            let dy = Double(landmarks[24].y - landmarks[23].y)
            let hipOrientation = atan2(dy, dx) * 180.0 / .pi
            
            // Добавляем сильную инерцию для таза
            let hipInertiaFactor = 0.95
            let newHipOrientation = lastValidOrientation * hipInertiaFactor + hipOrientation * (1 - hipInertiaFactor)
            
            // Проверяем резкие изменения ориентации
            let orientationDelta = abs(newHipOrientation - lastValidOrientation)
            if orientationDelta > 45.0 { // Если изменение больше 45 градусов
                // Используем более плавный переход
                let sign = (newHipOrientation - lastValidOrientation) > 0 ? 1.0 : -1.0
                return lastValidOrientation + sign * min(5.0, orientationDelta * 0.1)
            }
            
            return newHipOrientation
        }
        
        // Если таз не видим, используем комбинацию плеч и предыдущей ориентации
        var weightedOrientations: [(angle: Double, weight: Double)] = []
        let shoulderWeight = 0.2 // Уменьшаем вес плеч
        
        // Проверяем плечи только если они достаточно стабильны
        if let vis11 = landmarks[11].visibility?.floatValue,
           let vis12 = landmarks[12].visibility?.floatValue,
           vis11 > Constants.visibilityThreshold * 1.2, // Увеличиваем порог для плеч
           vis12 > Constants.visibilityThreshold * 1.2 {
            
            let dx = Double(landmarks[12].x - landmarks[11].x)
            let dy = Double(landmarks[12].y - landmarks[11].y)
            let shoulderOrientation = atan2(dy, dx) * 180.0 / .pi
            
            // Проверяем согласованность с предыдущей ориентацией
            let deltaFromLast = abs(shoulderOrientation - lastValidOrientation)
            if deltaFromLast < 30.0 { // Игнорируем слишком большие изменения
                weightedOrientations.append((angle: shoulderOrientation, weight: shoulderWeight))
            }
        }
        
        // Всегда учитываем предыдущую ориентацию с большим весом
        let previousWeight = 0.8 // Увеличиваем вес предыдущей ориентации
        weightedOrientations.append((angle: lastValidOrientation, weight: previousWeight))
        
        if !weightedOrientations.isEmpty {
            let totalWeight = weightedOrientations.reduce(0.0) { $0 + $1.weight }
            let weightedSum = weightedOrientations.reduce(0.0) { $0 + $1.angle * $1.weight }
            let newOrientation = weightedSum / totalWeight
            
            // Ограничиваем максимальное изменение ориентации
            let maxChange = 3.0 // Уменьшаем максимальное изменение за кадр
            let delta = newOrientation - lastValidOrientation
            let clampedDelta = max(-maxChange, min(maxChange, delta))
            
            return lastValidOrientation + clampedDelta
        }
        
        return lastValidOrientation
    }
    
    private func stabilizeOrientation(_ landmarks: [NormalizedLandmark], targetOrientation: Double) -> [NormalizedLandmark] {
        guard landmarks.count >= 33 else { return landmarks }
        
        var result = landmarks
        
        // Сначала стабилизируем голову и шею
        if let headIndex = Constants.anatomicalConstraints[0],
           let neckIndex = Constants.anatomicalConstraints[7] {
            let headWeight = Constants.stabilizationWeights[0] ?? 0.95
            let neckWeight = Constants.stabilizationWeights[7] ?? 0.9
            
            // Стабилизация шеи относительно плеч
            let avgShoulderX = (result[11].x + result[12].x) / 2
            let avgShoulderY = (result[11].y + result[12].y) / 2
            
            result[7] = NormalizedLandmark(
                x: result[7].x * (1 - neckWeight) + avgShoulderX * neckWeight,
                y: result[7].y * (1 - neckWeight) + avgShoulderY * neckWeight,
                z: result[7].z,
                visibility: result[7].visibility,
                presence: result[7].presence
            )
            
            // Стабилизация головы относительно шеи
            result[0] = NormalizedLandmark(
                x: result[0].x * (1 - headWeight) + result[7].x * headWeight,
                y: result[0].y * (1 - headWeight) + result[7].y * headWeight,
                z: result[0].z,
                visibility: result[0].visibility,
                presence: result[0].presence
            )
        }

        // Далее применяем стандартную стабилизацию для остального тела
        // Находим центр тела (между бедрами)
        let centerX = (result[23].x + result[24].x) / 2
        let centerY = (result[23].y + result[24].y) / 2
        
        // Применяем стабилизацию с учетом анатомических весов
        for (pointIndex, weight) in Constants.stabilizationWeights {
            if let constraints = Constants.anatomicalConstraints[pointIndex] {
                // Получаем среднее положение от связанных точек
                var avgX: Float = 0
                var avgY: Float = 0
                var totalWeight: Float = 0
                
                for constrainedPoint in constraints {
                    let constraintWeight = Constants.jointWeights[constrainedPoint] ?? 0.5
                    avgX += result[constrainedPoint].x * constraintWeight
                    avgY += result[constrainedPoint].y * constraintWeight
                    totalWeight += constraintWeight
                }
                
                if totalWeight > 0 {
                    avgX /= totalWeight
                    avgY /= totalWeight
                    
                    // Создаем новый landmark вместо модификации существующего
                    let landmark = result[pointIndex]
                    let stabilizedX = landmark.x * (1 - weight) + avgX * weight
                    let stabilizedY = landmark.y * (1 - weight) + avgY * weight
                    
                    result[pointIndex] = NormalizedLandmark(
                        x: stabilizedX,
                        y: stabilizedY,
                        z: landmark.z,
                        visibility: landmark.visibility,
                        presence: landmark.presence ?? NSNumber(value: 1.0)
                    )
                }
            }
        }
        
        // Стабилизируем таз отдельно с повышенной жесткостью
        let hipCenterX = (result[23].x + result[24].x) / 2
        let hipCenterY = (result[23].y + result[24].y) / 2
        let hipWidth = abs(result[23].x - result[24].x)
        
        result[23] = NormalizedLandmark(
            x: hipCenterX - hipWidth / 2,
            y: hipCenterY,
            z: result[23].z,
            visibility: result[23].visibility,
            presence: result[23].presence
        )
        
        result[24] = NormalizedLandmark(
            x: hipCenterX + hipWidth / 2,
            y: hipCenterY,
            z: result[24].z,
            visibility: result[24].visibility,
            presence: result[24].presence
        )

        // Создаем матрицу поворота
        let currentAngle = calculateSkeletonOrientation(result)
        let rotationAngle = targetOrientation - currentAngle
        let (cosAngle, sinAngle) = NumericConversion.rotationMatrix(angle: rotationAngle)
        
        // Применяем поворот ко всем точкам
        return result.map { landmark in
            let dx = landmark.x - centerX
            let dy = landmark.y - centerY
            
            return NormalizedLandmark(
                x: dx * cosAngle - dy * sinAngle + centerX,
                y: dx * sinAngle + dy * cosAngle + centerY,
                z: landmark.z,
                visibility: landmark.visibility,
                presence: landmark.presence ?? NSNumber(value: 1.0)
            )
        }
    }
    
    private func applyJointFlexibility(_ point: NormalizedLandmark,
                                     anchor: NormalizedLandmark,
                                     flexibility: Float) -> NormalizedLandmark {
        let dx = point.x - anchor.x
        let dy = point.y - anchor.y
        
        // Применяем гибкость к смещению
        let flexedX = anchor.x + dx * flexibility
        let flexedY = anchor.y + dy * flexibility
        
        return NormalizedLandmark(
            x: flexedX,
            y: flexedY,
            z: point.z,
            visibility: point.visibility,
            presence: point.presence ?? NSNumber(value: 1.0)
        )
    }
    
    private func detectAndHandleCrossover(_ landmarks: [NormalizedLandmark]) -> [NormalizedLandmark] {
        var result = landmarks
        
        guard result.count >= 33 else { return result }
        
        // Индексы ключевых точек для рук
        let leftArmPoints = [11, 13, 15] // левое плечо, локоть, запястье
        let rightArmPoints = [12, 14, 16] // правое плечо, локоть, запястье
        
        // Получаем текущие позиции рук
        let leftArm = leftArmPoints.map { result[$0] }
        let rightArm = rightArmPoints.map { result[$0] }
        
        // Определяем, происходит ли перекрещивание
        if isCrossing(leftArm, rightArm) {
            // Если есть предыдущие валидные позиции и скорости
            if let lastLeft = lastValidLeftArm,
               let lastRight = lastValidRightArm,
               !lastArmVelocities.isEmpty {
                
                // Предсказываем ожидаемые позиции на основе предыдущих движений
                let predictedLeft = predictPositions(lastLeft, velocities: lastArmVelocities.map { $0.left })
                let predictedRight = predictPositions(lastRight, velocities: lastArmVelocities.map { $0.right })
                
                // Определяем, какие точки к какой руке ближе
                let distanceToLeftPrediction = distance(between: leftArm, and: predictedLeft)
                let distanceToRightPrediction = distance(between: leftArm, and: predictedRight)
                
                // Если текущие точки ближе к предсказанным позициям противоположной руки,
                // значит произошла путаница и нужно их поменять местами
                if distanceToLeftPrediction > distanceToRightPrediction {
                    // Меняем точки местами с плавным переходом
                    for (i, leftIdx) in leftArmPoints.enumerated() {
                        let rightIdx = rightArmPoints[i]
                        let interpolatedLeft = interpolateLandmarks(from: result[rightIdx], to: predictedLeft[i], factor: 0.7)
                        let interpolatedRight = interpolateLandmarks(from: result[leftIdx], to: predictedRight[i], factor: 0.7)
                        result[leftIdx] = interpolatedLeft
                        result[rightIdx] = interpolatedRight
                    }
                }
            }
        } else {
            // Если перекрещивания нет, сохраняем позиции как валидные
            lastValidLeftArm = leftArm
            lastValidRightArm = rightArm
            
            // Обновляем скорости
            updateVelocities(leftArm: leftArm, rightArm: rightArm)
        }
        
        return result
    }
    
    private func isCrossing(_ leftArm: [NormalizedLandmark], _ rightArm: [NormalizedLandmark]) -> Bool {
        // Проверяем пересечение между сегментами рук
        let leftSegments = zip(leftArm.dropLast(), leftArm.dropFirst())
        let rightSegments = zip(rightArm.dropLast(), rightArm.dropFirst())
        
        for (l1, l2) in leftSegments {
            for (r1, r2) in rightSegments {
                if segmentsIntersect(p1: (l1.x, l1.y), p2: (l2.x, l2.y),
                                   p3: (r1.x, r1.y), p4: (r2.x, r2.y)) {
                    return true
                }
            }
        }
        return false
    }
    
    private func updateVelocities(leftArm: [NormalizedLandmark], rightArm: [NormalizedLandmark]) {
        guard let lastLeft = lastValidLeftArm,
              let lastRight = lastValidRightArm else {
            return
        }
        
        let leftVelocity = calculateVelocity(from: lastLeft, to: leftArm)
        let rightVelocity = calculateVelocity(from: lastRight, to: rightArm)
        
        lastArmVelocities.append((left: leftVelocity, right: rightVelocity))
        if lastArmVelocities.count > Constants.predictionWindowSize {
            lastArmVelocities.removeFirst()
        }
    }
    
    private func predictPositions(_ landmarks: [NormalizedLandmark], velocities: [CGVector]) -> [NormalizedLandmark] {
        guard !velocities.isEmpty else { return landmarks }
        
        let count = Double(velocities.count)
        let avgVelocity = velocities.reduce(CGVector.zero) { $0 + $1 }.scaled(by: 1.0 / count)
        let (dx, dy) = avgVelocity.floatComponents
        
        return landmarks.map { landmark in
            NormalizedLandmark(
                x: landmark.x + dx,
                y: landmark.y + dy,
                z: landmark.z,
                visibility: landmark.visibility,
                presence: landmark.presence ?? NSNumber(value: 1.0)
            )
        }
    }
    
    private func interpolateLandmarks(from: NormalizedLandmark, to: NormalizedLandmark, factor: Float) -> NormalizedLandmark {
        return NormalizedLandmark(
            x: from.x + (to.x - from.x) * factor,
            y: from.y + (to.y - from.y) * factor,
            z: from.z + (to.z - from.z) * factor,
            visibility: from.visibility,
            presence: from.presence ?? NSNumber(value: 1.0)
        )
    }
    
    // Добавляем недостающие вспомогательные методы
    private func distance(between points1: [NormalizedLandmark], and points2: [NormalizedLandmark]) -> Float {
        guard points1.count == points2.count else { return Float.infinity }
        
        var totalDistance: Float = 0
        for (p1, p2) in zip(points1, points2) {
            let dx = p1.x - p2.x
            let dy = p1.y - p2.y
            let dz = p1.z - p2.z
            totalDistance += sqrt(dx * dx + dy * dy + dz * dz)
        }
        
        return totalDistance / Float(points1.count)
    }
    
    private func segmentsIntersect(p1: (Float, Float), p2: (Float, Float),
                                 p3: (Float, Float), p4: (Float, Float)) -> Bool {
        // Вычисляем векторы
        let v1 = (x: p2.0 - p1.0, y: p2.1 - p1.1)
        let v2 = (x: p4.0 - p3.0, y: p4.1 - p3.1)
        
        // Вычисляем определитель
        let det = v1.x * v2.y - v1.y * v2.x
        
        // Если определитель близок к нулю, линии параллельны
        if abs(det) < 1e-6 { return false }
        
        // Вычисляем разницу между начальными точками
        let diff = (x: p3.0 - p1.0, y: p3.1 - p1.1)
        
        // Вычисляем параметры пересечения
        let t = (diff.x * v2.y - diff.y * v2.x) / det
        let u = (diff.x * v1.y - diff.y * v1.x) / det
        
        // Проверяем, находится ли точка пересечения внутри обоих отрезков
        return t >= 0 && t <= 1 && u >= 0 && u <= 1
    }
    
    private func calculateVelocity(from: [NormalizedLandmark], to: [NormalizedLandmark]) -> CGVector {
        guard from.count == to.count && !from.isEmpty else { return .zero }
        
        var totalDx: Double = 0
        var totalDy: Double = 0
        
        for (f, t) in zip(from, to) {
            totalDx += Double(t.x - f.x) // Явное приведение к Double
            totalDy += Double(t.y - f.y)
        }
        
        let count = Double(from.count)
        return CGVector(dx: totalDx / count, dy: totalDy / count)
    }
    
    private func isPoseStable(_ landmarks: [NormalizedLandmark]) -> Bool {
        // Проверяем ключевые точки (плечи, бедра, голова)
        let keyPoints = [0, 11, 12, 23, 24] // индексы ключевых точек
        var visibleCount = 0
        
        for index in keyPoints {
            if let visibility = landmarks[index].visibility?.floatValue,
               visibility > Constants.visibilityThreshold {
                visibleCount += 1
            }
        }
        
        // Поза считается стабильной, если видно достаточное количество ключевых точек
        return visibleCount >= Constants.minVisiblePoints
    }
    
    private func interpolateTowardStablePose(current: [NormalizedLandmark], stable: [NormalizedLandmark]) -> [NormalizedLandmark] {
        // Используем разные факторы интерполяции для видимых и невидимых точек
        return zip(current, stable).map { curr, stable in
            let visibility = curr.visibility?.floatValue ?? 0
            let factor: Float = visibility > Constants.visibilityThreshold ? 0.3 : 0.8
            
            return NormalizedLandmark(
                x: curr.x * (1 - factor) + stable.x * factor,
                y: curr.y * (1 - factor) + stable.y * factor,
                z: curr.z * (1 - factor) + stable.z * factor,
                visibility: visibility > Constants.visibilityThreshold ? curr.visibility : stable.visibility,
                presence: curr.presence ?? stable.presence ?? NSNumber(value: 1.0)
            )
        }
    }
    
    private func detectArmRaising(_ landmarks: [NormalizedLandmark]) {
        guard landmarks.count >= 33 else { return }
        
        let leftWrist = landmarks[15].y
        let rightWrist = landmarks[16].y
        
        if let lastPositions = lastArmPositionsY {
            let leftDelta = lastPositions.left - leftWrist
            let rightDelta = lastPositions.right - rightWrist
            
            // Определяем движение рук вверх, используя Float для сравнения
            let threshold: Float = Float(Constants.verticalMotionThreshold)
            isRaisingArms = leftDelta > threshold && rightDelta > threshold
        }
        
        lastArmPositionsY = (leftWrist, rightWrist)
    }

    private func stabilizeLegs(_ landmarks: [NormalizedLandmark]) -> [NormalizedLandmark] {
        var result = landmarks
        let originalPositions = landmarks
        
        // Индексы ключевых точек для ног
        let leftLegPoints = [23, 25, 27] // левое бедро, колено, стопа
        let rightLegPoints = [24, 26, 28] // правое бедро, колено, стопа
        
        // Получаем текущие позиции ног
        let leftLeg = leftLegPoints.map { result[$0] }
        let rightLeg = rightLegPoints.map { result[$0] }
        
        // Определяем пересечение ног
        if areLegsCrossing(leftLeg, rightLeg) {
            if let lastLeft = lastValidLeftLeg,
               let lastRight = lastValidRightLeg,
               !lastLegVelocities.isEmpty {
                
                // Предсказываем позиции на основе предыдущих движений
                let predictedLeft = predictPositions(lastLeft, velocities: lastLegVelocities.map { $0.left })
                let predictedRight = predictPositions(lastRight, velocities: lastLegVelocities.map { $0.right })
                
                // Определяем, какие точки к какой ноге ближе
                let distanceToLeftPrediction = distance(between: leftLeg, and: predictedLeft)
                let distanceToRightPrediction = distance(between: leftLeg, and: predictedRight)
                
                if distanceToLeftPrediction > distanceToRightPrediction {
                    // Меняем точки местами с плавным переходом
                    for (i, leftIdx) in leftLegPoints.enumerated() {
                        let rightIdx = rightLegPoints[i]
                        let interpolatedLeft = interpolateLandmarks(from: result[rightIdx], to: predictedLeft[i], factor: 0.7)
                        let interpolatedRight = interpolateLandmarks(from: result[leftIdx], to: predictedRight[i], factor: 0.7)
                        result[leftIdx] = interpolatedLeft
                        result[rightIdx] = interpolatedRight
                    }
                }
            }
        } else {
            // Если пересечения нет, сохраняем позиции
            lastValidLeftLeg = leftLeg
            lastValidRightLeg = rightLeg
            updateLegVelocities(leftLeg: leftLeg, rightLeg: rightLeg)
        }
        
        // Обрабатываем каждую ногу независимо
        for chain in Constants.legChains {
            // ... существующий код обработки ног ...
        }
        
        // Исправляем ошибку с изменением x координаты
        let minKneeDistance = Constants.legConstraints.kneeDistance * 0.5
        let kneeDistance = abs(result[25].x - result[26].x)
        
        if kneeDistance < minKneeDistance {
            let correction = (minKneeDistance - kneeDistance) * 0.2
            
            // Создаем новые лендмарки вместо модификации существующих
            result[25] = NormalizedLandmark(
                x: result[25].x - correction,
                y: result[25].y,
                z: result[25].z,
                visibility: result[25].visibility,
                presence: result[25].presence
            )
            
            result[26] = NormalizedLandmark(
                x: result[26].x + correction,
                y: result[26].y,
                z: result[26].z,
                visibility: result[26].visibility,
                presence: result[26].presence
            )
        }
        
        return result
    }

    private func handleInvisibleLimbs(_ landmarks: [NormalizedLandmark]) -> [NormalizedLandmark] {
        var result = landmarks
        
        // Добавляем особую обработку головы и лица
        let facePoints = [0, 1, 2, 3, 4, 5, 6, 7] // Точки головы и лица
        var visibleFacePoints = 0
        var needsPrediction = false
        
        // Проверяем видимость точек лица
        for pointIndex in facePoints {
            if let visibility = result[pointIndex].visibility?.floatValue,
               visibility > Constants.headStabilization.facePointsThreshold {
                visibleFacePoints += 1
            }
        }
        
        // Если большинство точек лица не видно, используем предсказание
        if visibleFacePoints < Constants.headStabilization.minNeckPoints {
            needsPrediction = true
            missingFramesCount += 1
        } else {
            // Обновляем историю и скорости точек лица
            let currentFacePoints = facePoints.map { result[$0] }
            facePointsHistory.append(currentFacePoints)
            if facePointsHistory.count > Constants.facePrediction.historySize {
                facePointsHistory.removeFirst()
            }
            
            // Обновляем скорости
            if let lastPoints = lastValidFacePoints {
                let velocities = zip(lastPoints, currentFacePoints).map { last, current in
                    CGVector(
                        dx: Double(current.x - last.x),
                        dy: Double(current.y - last.y)
                    )
                }
                facePointsVelocities = velocities
            }
            
            lastValidFacePoints = currentFacePoints
            missingFramesCount = 0
        }
        
        // Если нужно предсказание и у нас есть история
        if needsPrediction && missingFramesCount <= Constants.facePrediction.maxPredictionFrames,
           let lastValid = lastValidFacePoints,
           !facePointsVelocities.isEmpty {
            
            // Предсказываем новые позиции для каждой точки лица
            for (i, pointIndex) in facePoints.enumerated() {
                let velocity = facePointsVelocities[i]
                let lastPoint = lastValid[i]
                
                // Ограничиваем скорость изменения положения
                let dx = Float(velocity.dx)
                let dy = Float(velocity.dy)
                let speed = sqrt(dx * dx + dy * dy)
                let speedFactor = speed > Constants.facePrediction.maxSpeed ?
                    Constants.facePrediction.maxSpeed / speed : 1.0
                
                // Применяем предсказание с затуханием
                let decayFactor = pow(Constants.facePrediction.smoothing,
                                    Float(missingFramesCount))
                
                let predictedX = lastPoint.x + dx * speedFactor * decayFactor
                let predictedY = lastPoint.y + dy * speedFactor * decayFactor
                
                result[pointIndex] = NormalizedLandmark(
                    x: predictedX,
                    y: predictedY,
                    z: lastPoint.z,
                    visibility: NSNumber(value: Constants.facePrediction.confidence * decayFactor),
                    presence: lastPoint.presence
                )
            }
        }
        
        // Обрабатываем остальные конечности
        let limbs = [15, 16, 27, 28] // кисти и стопы
        for limbIndex in limbs {
            if let visibility = result[limbIndex].visibility?.floatValue,
               visibility < Constants.invisibilityHandling.minConfidence,
               let lastStable = lastStablePose?[limbIndex] {
                
                result[limbIndex] = NormalizedLandmark(
                    x: result[limbIndex].x * (1 - Constants.invisibilityHandling.fadeOutSpeed) +
                       lastStable.x * Constants.invisibilityHandling.fadeOutSpeed,
                    y: result[limbIndex].y,  // Сохраняем Y для плавности
                    z: result[limbIndex].z,
                    visibility: NSNumber(value: visibility),
                    presence: result[limbIndex].presence
                )
            }
        }

        // Добавляем проверку минимального расстояния между точками лица
        let facePointsIndices = [1, 2, 3, 4, 5, 6] // Точки лица (без головы и шеи)
        for i in 0..<facePointsIndices.count {
            for j in (i + 1)..<facePointsIndices.count {
                let p1 = result[facePointsIndices[i]]
                let p2 = result[facePointsIndices[j]]
                
                let dx = p2.x - p1.x
                let dy = p2.y - p1.y
                let distance = sqrt(dx * dx + dy * dy)
                
                // Если точки слишком близко, отодвигаем их
                if distance < Constants.faceConfiguration.minDistance {
                    let factor = Constants.faceConfiguration.minDistance / max(distance, 0.001)
                    let offsetX = dx * (factor - 1) * 0.5
                    let offsetY = dy * (factor - 1) * 0.5
                    
                    // Смещаем точки в противоположных направлениях
                    result[facePointsIndices[i]] = NormalizedLandmark(
                        x: p1.x - offsetX,
                        y: p1.y - offsetY,
                        z: p1.z,
                        visibility: p1.visibility,
                        presence: p1.presence
                    )
                    
                    result[facePointsIndices[j]] = NormalizedLandmark(
                        x: p2.x + offsetX,
                        y: p2.y + offsetY,
                        z: p2.z,
                        visibility: p2.visibility,
                        presence: p2.presence
                    )
                }
            }
        }
        
        return result
    }

    private func handleOutOfFrame(_ landmarks: [NormalizedLandmark]) -> [NormalizedLandmark] {
        var result = landmarks
        
        // Специальная обработка головы при выходе из кадра
        if let headVis = result[0].visibility?.floatValue,
           headVis < Constants.visibilityThreshold,
           let lastStable = lastStablePose?[0] {
            
            let decay = Constants.outOfFrameHandling.headDecay
            result[0] = NormalizedLandmark(
                x: result[0].x * (1 - decay) + lastStable.x * decay,
                y: result[0].y,  // Сохраняем Y для плавности
                z: result[0].z,
                visibility: result[0].visibility,
                presence: result[0].presence
            )
        }
        
        return result
    }

    private func areLegsCrossing(_ leftLeg: [NormalizedLandmark], _ rightLeg: [NormalizedLandmark]) -> Bool {
        let leftSegments = zip(leftLeg.dropLast(), leftLeg.dropFirst())
        let rightSegments = zip(rightLeg.dropLast(), rightLeg.dropFirst())
        
        for (l1, l2) in leftSegments {
            for (r1, r2) in rightSegments {
                if segmentsIntersect(p1: (l1.x, l1.y), p2: (l2.x, l2.y),
                                   p3: (r1.x, r1.y), p4: (r2.x, r2.y)) {
                    return true
                }
            }
        }
        return false
    }

    private func updateLegVelocities(leftLeg: [NormalizedLandmark], rightLeg: [NormalizedLandmark]) {
        guard let lastLeft = self.lastValidLeftLeg,
              let lastRight = self.lastValidRightLeg else {
            return
        }
        
        let leftVelocity = self.calculateVelocity(from: lastLeft, to: leftLeg)
        let rightVelocity = self.calculateVelocity(from: lastRight, to: rightLeg)
        
        self.lastLegVelocities.append((left: leftVelocity, right: rightVelocity))
        if self.lastLegVelocities.count > Constants.predictionWindowSize {
            self.lastLegVelocities.removeFirst()
        }
    }
}

// Вспомогательные расширения
private extension CGVector {
    static var zero: CGVector { CGVector(dx: 0, dy: 0) }
    
    static func + (lhs: CGVector, rhs: CGVector) -> CGVector {
        return CGVector(dx: lhs.dx + rhs.dx, dy: lhs.dy + rhs.dy)
    }
    
    func scaled(by factor: Double) -> CGVector {
        return CGVector(dx: self.dx * factor, dy: self.dy * factor)
    }
}
