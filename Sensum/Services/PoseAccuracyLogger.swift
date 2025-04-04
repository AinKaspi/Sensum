import Foundation
import MediaPipeTasksVision
import UIKit

class PoseAccuracyLogger {
    // Синглтон для доступа из разных частей приложения
    static let shared = PoseAccuracyLogger()
    
    // Количество собранных образцов для статистики
    private var sampleCount: Int = 0
    
    // Частота дрожания ключевых точек (jitter)
    private var jitterValues: [Double] = []
    
    // Уверенность в ключевых точках
    private var confidenceValues: [Double] = []
    
    // Время обновления результатов
    private var updateTimesMs: [Double] = []
    
    // Последние обработанные ключевые точки
    private var lastLandmarks: [[NormalizedLandmark]] = []
    
    // Настройки логирования
    var isLoggingEnabled = true
    var sampleFrequency = 10  // Логировать каждый N-й кадр
    
    // Приватный инициализатор для синглтона
    private init() {}
    
    // Обновление метрик с новыми данными
    func updateMetrics(landmarks: [[NormalizedLandmark]], inferenceTime: Double) {
        guard isLoggingEnabled else { return }
        
        // Логируем только каждый N-й кадр для оптимизации
        sampleCount += 1
        if sampleCount % sampleFrequency != 0 {
            return
        }
        
        // Обновляем время инференса
        updateTimesMs.append(inferenceTime)
        
        // Если у нас есть предыдущие ключевые точки, рассчитаем jitter
        if !lastLandmarks.isEmpty && !landmarks.isEmpty {
            let jitter = calculateJitter(previous: lastLandmarks[0], current: landmarks[0])
            jitterValues.append(jitter)
        }
        
        // Рассчитываем среднюю уверенность в ключевых точках
        if !landmarks.isEmpty {
            let confidence = calculateAverageConfidence(landmarks: landmarks[0])
            confidenceValues.append(confidence)
        }
        
        // Сохраняем текущие ключевые точки для следующего сравнения
        lastLandmarks = landmarks
        
        // Логируем текущие метрики каждые 100 выборок
        if sampleCount % 100 == 0 {
            logCurrentMetrics()
        }
    }
    
    // Расчет "дрожания" между кадрами (чем меньше, тем стабильнее)
    private func calculateJitter(previous: [NormalizedLandmark], current: [NormalizedLandmark]) -> Double {
        guard previous.count == current.count, !previous.isEmpty else {
            return 0.0
        }
        
        var totalJitter: Double = 0.0
        
        for i in 0..<previous.count {
            let dx = Double(current[i].x - previous[i].x)
            let dy = Double(current[i].y - previous[i].y)
            let dz = Double(current[i].z - previous[i].z)
            
            // Евклидово расстояние между точками
            let distance = sqrt(dx*dx + dy*dy + dz*dz)
            totalJitter += distance
        }
        
        return totalJitter / Double(previous.count)
    }
    
    // Расчет средней уверенности в ключевых точках
    private func calculateAverageConfidence(landmarks: [NormalizedLandmark]) -> Double {
        var totalConfidence: Double = 0.0
        var pointsWithConfidence: Int = 0
        
        for landmark in landmarks {
            if let visibility = landmark.visibility {
                totalConfidence += Double(visibility)
                pointsWithConfidence += 1
            }
        }
        
        return pointsWithConfidence > 0 ? totalConfidence / Double(pointsWithConfidence) : 0.0
    }
    
    // Вывод текущих метрик в лог
    private func logCurrentMetrics() {
        var logMessage = "======= POSE DETECTION METRICS =======\n"
        
        // Среднее время обновления
        if !updateTimesMs.isEmpty {
            let avgUpdateTime = updateTimesMs.reduce(0, +) / Double(updateTimesMs.count)
            logMessage += String(format: "Average inference time: %.2f ms\n", avgUpdateTime)
        }
        
        // Средняя стабильность (противоположность дрожанию)
        if !jitterValues.isEmpty {
            let avgJitter = jitterValues.reduce(0, +) / Double(jitterValues.count)
            logMessage += String(format: "Average jitter: %.5f (lower is better)\n", avgJitter)
        }
        
        // Средняя уверенность
        if !confidenceValues.isEmpty {
            let avgConfidence = confidenceValues.reduce(0, +) / Double(confidenceValues.count)
            logMessage += String(format: "Average confidence: %.3f (higher is better)\n", avgConfidence)
        }
        
        logMessage += "====================================="
        
        // Выводим в консоль и экспортируем в файл лога
        print(logMessage)
        exportToFile(metrics: logMessage)
    }
    
    // Сброс накопленной статистики
    func resetMetrics() {
        sampleCount = 0
        jitterValues.removeAll()
        confidenceValues.removeAll()
        updateTimesMs.removeAll()
        lastLandmarks.removeAll()
    }
    
    // Получение текущих метрик для отображения в интерфейсе
    func getCurrentMetrics() -> [String: Double] {
        var metrics: [String: Double] = [:]
        
        if !updateTimesMs.isEmpty {
            metrics["avgInferenceTime"] = updateTimesMs.reduce(0, +) / Double(updateTimesMs.count)
        }
        if !jitterValues.isEmpty {
            metrics["avgJitter"] = jitterValues.reduce(0, +) / Double(jitterValues.count)
        }
        if !confidenceValues.isEmpty {
            metrics["avgConfidence"] = confidenceValues.reduce(0, +) / Double(confidenceValues.count)
        }
        
        return metrics
    }
    
    // Экспорт метрик в файл лога
    private func exportToFile(metrics: String) {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        
        let fileURL = documentsDirectory.appendingPathComponent("pose_metrics_\(timestamp).txt")
        
        do {
            try metrics.write(to: fileURL, atomically: true, encoding: .utf8)
            print("Metrics exported to \(fileURL.path)")
        } catch {
            print("Failed to export metrics: \(error)")
        }
    }
}
