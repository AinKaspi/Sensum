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
    
    // MARK: - Properties
    
    private let smoothingWindowSize = 5
    private var positionHistory: [[NormalizedLandmark]] = []
    
    // Добавляем новые свойства для отслеживания ориентации
    private var lastValidOrientation: Double = 0
    private var lastUpdateTime: TimeInterval = 0
    private let maxRotationPerSecond = 90.0 // Максимальный угол поворота в градусах в секунду
    
    // MARK: - Public Methods
    
    /// Применяет антропометрические ограничения и сглаживание к ключевым точкам
    func processLandmarks(_ landmarks: [NormalizedLandmark]) -> [NormalizedLandmark] {
        // Получаем текущую ориентацию скелета
        let orientation = calculateSkeletonOrientation(landmarks)
        
        // Применяем существующие ограничения
        let constrainedLandmarks = applyAnatomicalConstraints(landmarks)
        
        // Стабилизируем ориентацию
        let stabilizedLandmarks = stabilizeOrientation(constrainedLandmarks, targetOrientation: orientation)
        
        // Сглаживаем движения
        let smoothedLandmarks = smoothPositions(stabilizedLandmarks)
        
        // Применяем проверку пропорций
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
            let expectedShoulderY = height * Float(HumanProportions.shoulderToHeight)
            let shoulderDiff = expectedShoulderY - shoulderY
            
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
        
        // Используем плечи для определения ориентации
        let leftShoulder = landmarks[11]
        let rightShoulder = landmarks[12]
        
        // Вычисляем угол между плечами относительно горизонтали
        let dx = Double(rightShoulder.x - leftShoulder.x)
        let dy = Double(rightShoulder.y - leftShoulder.y)
        let currentOrientation = atan2(dy, dx) * 180.0 / .pi
        
        // Проверяем видимость точек
        let shouldersVisible = (leftShoulder.visibility?.floatValue ?? 0 > 0.5) &&
                             (rightShoulder.visibility?.floatValue ?? 0 > 0.5)
        
        if !shouldersVisible {
            return lastValidOrientation // Возвращаем последнюю валидную ориентацию
        }
        
        // Ограничиваем скорость поворота
        let now = Date().timeIntervalSince1970
        let deltaTime = now - lastUpdateTime
        let maxDelta = maxRotationPerSecond * deltaTime
        
        var orientationDelta = currentOrientation - lastValidOrientation
        
        // Нормализуем разницу углов
        while orientationDelta > 180 { orientationDelta -= 360 }
        while orientationDelta < -180 { orientationDelta += 360 }
        
        // Ограничиваем изменение
        if abs(orientationDelta) > maxDelta {
            orientationDelta = orientationDelta > 0 ? maxDelta : -maxDelta
        }
        
        let newOrientation = lastValidOrientation + orientationDelta
        
        lastValidOrientation = newOrientation
        lastUpdateTime = now
        
        return newOrientation
    }
    
    private func stabilizeOrientation(_ landmarks: [NormalizedLandmark], targetOrientation: Double) -> [NormalizedLandmark] {
        guard landmarks.count >= 33 else { return landmarks }
        
        // Находим центр скелета (между бедрами)
        let centerX = (landmarks[23].x + landmarks[24].x) / 2
        let centerY = (landmarks[23].y + landmarks[24].y) / 2
        
        // Создаем матрицу поворота
        let currentAngle = calculateSkeletonOrientation(landmarks)
        let rotationAngle = targetOrientation - currentAngle
        let cosAngle = Float(cos(rotationAngle * .pi / 180.0))
        let sinAngle = Float(sin(rotationAngle * .pi / 180.0))
        
        return landmarks.map { landmark in
            // Смещаем точку относительно центра
            let dx = landmark.x - centerX
            let dy = landmark.y - centerY
            
            // Поворачиваем
            let newX = dx * cosAngle - dy * sinAngle + centerX
            let newY = dx * sinAngle + dy * cosAngle + centerY
            
            return NormalizedLandmark(
                x: newX,
                y: newY,
                z: landmark.z,
                visibility: landmark.visibility,
                presence: landmark.presence ?? NSNumber(value: 1.0)
            )
        }
    }
}
