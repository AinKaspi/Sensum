import CoreGraphics
import MediaPipeTasksVision

enum NumericConversion {
    // Конвертация CGVector в пару Float значений
    static func toFloat(_ vector: CGVector) -> (dx: Float, dy: Float) {
        return (Float(vector.dx), Float(vector.dy))
    }
    
    // Создание CGVector из Float значений
    static func toCGVector(dx: Float, dy: Float) -> CGVector {
        return CGVector(dx: Double(dx), dy: Double(dy))
    }
    
    // Конвертация Double в Float с явным указанием
    static func toFloat(_ value: Double) -> Float {
        return Float(value)
    }
    
    // Конвертация угла из радиан в градусы для Float
    static func radiansToDegrees(_ radians: Float) -> Float {
        return radians * 180.0 / .pi
    }
    
    // Вспомогательная функция для работы с матрицами поворота
    static func rotationMatrix(angle: Double) -> (cos: Float, sin: Float) {
        return (Float(cos(angle * .pi / 180.0)),
                Float(sin(angle * .pi / 180.0)))
    }
}

// Расширение для более удобной работы с CGVector
extension CGVector {
    // Конвертация в float tuple
    var floatComponents: (dx: Float, dy: Float) {
        return NumericConversion.toFloat(self)
    }
    
    // Создание вектора из float значений
    static func fromFloat(dx: Float, dy: Float) -> CGVector {
        return NumericConversion.toCGVector(dx: dx, dy: dy)
    }
}

// Расширение для NormalizedLandmark для работы с векторами
extension NormalizedLandmark {
    // Вычисление вектора между двумя точками
    static func vector(from: NormalizedLandmark, to: NormalizedLandmark) -> CGVector {
        return CGVector.fromFloat(
            dx: to.x - from.x,
            dy: to.y - from.y
        )
    }
}
