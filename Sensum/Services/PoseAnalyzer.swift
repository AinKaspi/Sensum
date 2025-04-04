import Foundation
import MediaPipeTasksVision
import CoreGraphics

class PoseAnalyzer {
    
    // MARK: - Типы углов для анализа
    enum JointAngle {
        case elbow(side: BodySide)
        case knee(side: BodySide)
        case hip(side: BodySide)
        case shoulder(side: BodySide)
    }
    
    enum BodySide {
        case left
        case right
    }
    
    // MARK: - Индексы ключевых точек MediaPipe Pose
    private enum PoseLandmark {
        static let leftShoulder = 11
        static let rightShoulder = 12
        static let leftElbow = 13
        static let rightElbow = 14
        static let leftWrist = 15
        static let rightWrist = 16
        static let leftHip = 23
        static let rightHip = 24
        static let leftKnee = 25
        static let rightKnee = 26
        static let leftAnkle = 27
        static let rightAnkle = 28
    }
    
    // MARK: - Публичные методы
    
    /// Рассчитывает угол в градусах между тремя точками
    static func calculateAngle(point1: NormalizedLandmark, point2: NormalizedLandmark, point3: NormalizedLandmark) -> Double {
        let vector1 = CGVector(dx: Double(point1.x - point2.x), dy: Double(point1.y - point2.y))
        let vector2 = CGVector(dx: Double(point3.x - point2.x), dy: Double(point3.y - point2.y))
        
        let dot = vector1.dx * vector2.dx + vector1.dy * vector2.dy
        let det = vector1.dx * vector2.dy - vector1.dy * vector2.dx
        
        let angle = atan2(det, dot)
        
        // Переводим радианы в градусы и нормализуем от 0 до 180
        let degrees = abs(angle * 180.0 / .pi)
        return degrees
    }
    
    /// Получает угол для конкретного сустава
    static func getJointAngle(landmarks: [NormalizedLandmark], joint: JointAngle) -> Double? {
        guard landmarks.count >= 33 else { return nil }
        
        switch joint {
        case .elbow(let side):
            let (shoulder, elbow, wrist) = side == .left ?
                (PoseLandmark.leftShoulder, PoseLandmark.leftElbow, PoseLandmark.leftWrist) :
                (PoseLandmark.rightShoulder, PoseLandmark.rightElbow, PoseLandmark.rightWrist)
            
            return calculateAngle(
                point1: landmarks[shoulder],
                point2: landmarks[elbow],
                point3: landmarks[wrist]
            )
            
        case .knee(let side):
            let (hip, knee, ankle) = side == .left ?
                (PoseLandmark.leftHip, PoseLandmark.leftKnee, PoseLandmark.leftAnkle) :
                (PoseLandmark.rightHip, PoseLandmark.rightKnee, PoseLandmark.rightAnkle)
            
            return calculateAngle(
                point1: landmarks[hip],
                point2: landmarks[knee],
                point3: landmarks[ankle]
            )
            
        case .hip(let side):
            let (shoulder, hip, knee) = side == .left ?
                (PoseLandmark.leftShoulder, PoseLandmark.leftHip, PoseLandmark.leftKnee) :
                (PoseLandmark.rightShoulder, PoseLandmark.rightHip, PoseLandmark.rightKnee)
            
            return calculateAngle(
                point1: landmarks[shoulder],
                point2: landmarks[hip],
                point3: landmarks[knee]
            )
            
        case .shoulder(let side):
            let (elbow, shoulder, hip) = side == .left ?
                (PoseLandmark.leftElbow, PoseLandmark.leftShoulder, PoseLandmark.leftHip) :
                (PoseLandmark.rightElbow, PoseLandmark.rightShoulder, PoseLandmark.rightHip)
            
            return calculateAngle(
                point1: landmarks[elbow],
                point2: landmarks[shoulder],
                point3: landmarks[hip]
            )
        }
    }
    
    /// Анализирует полную позу и возвращает все основные углы
    static func analyzePose(landmarks: [NormalizedLandmark]) -> [String: Double] {
        var angles: [String: Double] = [:]
        
        // Анализ локтей
        if let leftElbowAngle = getJointAngle(landmarks: landmarks, joint: .elbow(side: .left)) {
            angles["leftElbow"] = leftElbowAngle
        }
        if let rightElbowAngle = getJointAngle(landmarks: landmarks, joint: .elbow(side: .right)) {
            angles["rightElbow"] = rightElbowAngle
        }
        
        // Анализ колен
        if let leftKneeAngle = getJointAngle(landmarks: landmarks, joint: .knee(side: .left)) {
            angles["leftKnee"] = leftKneeAngle
        }
        if let rightKneeAngle = getJointAngle(landmarks: landmarks, joint: .knee(side: .right)) {
            angles["rightKnee"] = rightKneeAngle
        }
        
        // Анализ бедер
        if let leftHipAngle = getJointAngle(landmarks: landmarks, joint: .hip(side: .left)) {
            angles["leftHip"] = leftHipAngle
        }
        if let rightHipAngle = getJointAngle(landmarks: landmarks, joint: .hip(side: .right)) {
            angles["rightHip"] = rightHipAngle
        }
        
        // Анализ плеч
        if let leftShoulderAngle = getJointAngle(landmarks: landmarks, joint: .shoulder(side: .left)) {
            angles["leftShoulder"] = leftShoulderAngle
        }
        if let rightShoulderAngle = getJointAngle(landmarks: landmarks, joint: .shoulder(side: .right)) {
            angles["rightShoulder"] = rightShoulderAngle
        }
        
        return angles
    }
}
