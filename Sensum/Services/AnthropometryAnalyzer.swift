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
        static let predictionWindowSize = 3
        static let minVisiblePoints = 4 // Минимальное количество видимых точек для валидной позы
        static let visibilityThreshold: Float = 0.5 // Порог видимости точки
        static let stabilityTimeout: TimeInterval = 0.5 // Время удержания последней стабильной позы
        
        // Добавляем константы для гибкости суставов
        static let shoulderFlexibility: Float = 0.7  // Гибкость плечевого пояса
        static let spineFlexibility: Float = 0.5    // Гибкость позвоночника
        static let verticalMotionThreshold = 0.1    // Порог для определения вертикального движения
        static let shoulderTensionReduction: Float = 0.3   // Уменьшение напряжения между плечами при поднятии рук

        // Веса точек (имитация массы тела)
        static let jointWeights: [Int: Float] = [
            0: 0.8,   // голова
            11: 0.6,  // левое плечо
            12: 0.6,  // правое плечо
            23: 1.0,  // левое бедро (центр тяжести)
            24: 1.0,  // правое бедро
            15: 0.2,  // левая кисть
            16: 0.2,  // правая кисть
            27: 0.4,  // левая стопа
            28: 0.4   // правая стопа
        ]
        
        // Цепочки влияния (от центра к конечностям)
        static let influenceChains: [[Int]] = [
            [23, 24, 11, 13, 15],  // центр -> левая рука
            [23, 24, 12, 14, 16],  // центр -> правая рука
            [23, 25, 27],          // центр -> левая нога
            [24, 26, 28]           // центр -> правая нога
        ]
        
        static let stabilityFactors = (
            lowVisibility: 0.3,    // Множитель влияния при низкой видимости
            distanceDecay: 0.8,    // Затухание влияния с расстоянием
            inertiaFactor: 0.7     // Фактор инерции для стабильности
        )
    }
    
    // MARK: - Properties
    
    private let smoothingWindowSize = 5
    private var positionHistory: [[NormalizedLandmark]] = []
    
    // Добавляем новые свойства для отслеживания ориентации
    private var lastValidOrientation: Double = 0
    private var lastUpdateTime: TimeInterval = 0
    private let maxRotationPerSecond = 90.0 // Максимальный угол поворота в градусах в секунду
    
    // Добавляем свойства для отслеживания конечностей
    private var lastValidLeftArm: [NormalizedLandmark]?
    private var lastValidRightArm: [NormalizedLandmark]?
    private var lastArmVelocities: [(left: CGVector, right: CGVector)] = []
    
    // Добавляем новые свойства для отслеживания стабильности
    private var lastStableTimestamp: TimeInterval = 0
    private var lastStablePose: [NormalizedLandmark]?
    private var isStabilizing = false
    
    // Добавляем отслеживание вертикального движения рук
    private var lastArmPositionsY: (left: Float, right: Float)?
    private var isRaisingArms = false
    
    // MARK: - Public Methods
    
    /// Применяет антропометрические ограничения и сглаживание к ключевым точкам
    func processLandmarks(_ landmarks: [NormalizedLandmark]) -> [NormalizedLandmark] {
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
        
        // Затем применяем остальные обработки
        let constrainedLandmarks = applyAnatomicalConstraints(crossoverHandledLandmarks)
        let orientation = calculateSkeletonOrientation(constrainedLandmarks)
        let stabilizedLandmarks = stabilizeOrientation(constrainedLandmarks, targetOrientation: orientation)
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
        // Добавляем текущие позиции в историю
        positionHistory.append(landmarks)
        if positionHistory.count > smoothingWindowSize {
            positionHistory.removeFirst()
        }
        
        // Если недостаточно истории, возвращаем текущие позиции
        guard positionHistory.count == smoothingWindowSize else {
            return landmarks
        }
        
        // Применяем фильтр скользящего среднего с весами
        return landmarks.enumerated().map { index, _ in
            var sumX: Float = 0
            var sumY: Float = 0
            var sumZ: Float = 0
            var sumVisibility: Float = 0
            var weightSum: Float = 0
            
            for (historyIndex, historical) in positionHistory.enumerated() {
                let weight = Float(historyIndex + 1)
                sumX += historical[index].x * weight
                sumY += historical[index].y * weight
                sumZ += historical[index].z * weight
                if let visibility = historical[index].visibility?.floatValue {
                    sumVisibility += visibility * weight
                }
                weightSum += weight
            }
            
            let smoothedLandmark = NormalizedLandmark(
                x: sumX / weightSum,
                y: sumY / weightSum,
                z: sumZ / weightSum,
                visibility: NSNumber(value: sumVisibility / weightSum),
                presence: NSNumber(value: 1.0)  // Добавляем presence
            )
            return smoothedLandmark
        }
    }
    
    private func validateJointAngles(_ landmarks: [NormalizedLandmark]) -> Bool {
        // Проверяем углы в локтях
        let leftElbowAngle = calculateAngle(landmarks[11], landmarks[13], landmarks[15])
        let rightElbowAngle = calculateAngle(landmarks[12], landmarks[14], landmarks[16])
        
        if leftElbowAngle < HumanProportions.elbowRange.min || leftElbowAngle > HumanProportions.elbowRange.max ||
           rightElbowAngle < HumanProportions.elbowRange.min || rightElbowAngle > HumanProportions.elbowRange.max {
            return false
        }
        
        // Проверяем углы в коленях
        let leftKneeAngle = calculateAngle(landmarks[23], landmarks[25], landmarks[27])
        let rightKneeAngle = calculateAngle(landmarks[24], landmarks[26], landmarks[28])
        
        if leftKneeAngle < HumanProportions.kneeRange.min || leftKneeAngle > HumanProportions.kneeRange.max ||
           rightKneeAngle < HumanProportions.kneeRange.min || rightKneeAngle > HumanProportions.kneeRange.max {
            return false
        }
        
        return true
    }
    
    private func applyAnatomicalConstraints(_ landmarks: [NormalizedLandmark]) -> [NormalizedLandmark] {
        var constrained = landmarks
        
        // Применяем ограничения на углы суставов
        if constrained.count >= 33 {
            // Ограничиваем углы в локтях
            constrained[13] = constrainElbowPosition(constrained[13], constrained[11], constrained[15])
            constrained[14] = constrainElbowPosition(constrained[14], constrained[12], constrained[16])
            
            // Ограничиваем углы в коленях
            constrained[25] = constrainKneePosition(constrained[25], constrained[23], constrained[27])
            constrained[26] = constrainKneePosition(constrained[26], constrained[24], constrained[28])
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
        
        var weightedOrientations: [(angle: Double, weight: Double)] = []
        
        // Проходим по цепочкам влияния
        for chain in Constants.influenceChains {
            var chainWeight: Double = 1.0
            var lastValidPoint: Int?
            
            for (i, pointIndex) in chain.enumerated() {
                let point = landmarks[pointIndex]
                
                // Проверяем видимость и уверенность в точке
                if let visibility = point.visibility?.floatValue,
                   visibility > Constants.visibilityThreshold {
                    
                    // Если есть предыдущая валидная точка, считаем ориентацию сегмента
                    if let lastIdx = lastValidPoint {
                        let lastPoint = landmarks[lastIdx]
                        
                        // Рассчитываем угол сегмента
                        let dx = Double(point.x - lastPoint.x)
                        let dy = Double(point.y - lastPoint.y)
                        let angle = atan2(dy, dx) * 180.0 / .pi
                        
                        // Вычисляем вес с учетом:
                        // - массы точек
                        // - расстояния от центра (decay)
                        // - видимости
                        let pointWeight = Double(Constants.jointWeights[pointIndex] ?? 0.5)
                        let distanceDecay = pow(Double(Constants.stabilityFactors.distanceDecay), Double(i))
                        let visibilityFactor = Double(visibility)
                        
                        let totalWeight = pointWeight * distanceDecay * visibilityFactor * chainWeight
                        weightedOrientations.append((angle: angle, weight: totalWeight))
                    }
                    
                    lastValidPoint = pointIndex
                } else {
                    // Если точка не видна, уменьшаем вес всей последующей цепочки
                    chainWeight *= Double(Constants.stabilityFactors.lowVisibility)
                }
            }
        }
        
        if !weightedOrientations.isEmpty {
            let totalWeight = weightedOrientations.reduce(0.0) { $0 + $1.weight }
            let weightedSum = weightedOrientations.reduce(0.0) { $0 + $1.angle * $1.weight }
            let newOrientation = weightedSum / totalWeight
            
            // Применяем инерцию для стабильности
            let inertiaFactor = Double(Constants.stabilityFactors.inertiaFactor)
            return lastValidOrientation * inertiaFactor + newOrientation * (1 - inertiaFactor)
        }
        
        return lastValidOrientation
    }
    
    private func stabilizeOrientation(_ landmarks: [NormalizedLandmark], targetOrientation: Double) -> [NormalizedLandmark] {
        guard landmarks.count >= 33 else { return landmarks }
        
        var result = landmarks
        
        // Добавляем гибкость плечевого пояса
        let shoulderIndices = [11, 12] // левое и правое плечо
        if isRaisingArms {
            for i in shoulderIndices {
                result[i] = applyJointFlexibility(result[i],
                                                anchor: result[i-1], // относительно соседней точки
                                                flexibility: Constants.shoulderFlexibility)
            }
        }
        
        // Добавляем гибкость позвоночника
        let spineIndices = [23, 24] // точки таза
        for i in spineIndices {
            result[i] = applyJointFlexibility(result[i],
                                            anchor: result[i-1],
                                            flexibility: Constants.spineFlexibility)
        }
        
        // Находим центр скелета (между бедрами)
        let centerX = (result[23].x + result[24].x) / 2
        let centerY = (result[23].y + result[24].y) / 2
        
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
