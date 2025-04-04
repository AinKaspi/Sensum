// Copyright 2023 The MediaPipe Authors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// ЧТО ЭТО: Этот файл содержит код, который помогает находить и отслеживать позы людей на изображениях, видео и в реальном времени с камеры.
//
// ЗАЧЕМ ЭТО НУЖНО: Этот код позволяет вашему приложению распознавать, как стоит или двигается человек.
// Например, приложение может определить, поднял ли человек руку или в какой позе он находится.
//
// КАК ЭТО РАБОТАЕТ: Мы используем специальную технологию от Google под названием MediaPipe,
// которая с помощью искусственного интеллекта находит ключевые точки тела человека (голова, плечи, локти, колени и т.д.).

import UIKit
import MediaPipeTasksVision
import AVFoundation

// ЧТО ЭТО: Протокол - это набор методов, которые должен реализовать класс, желающий получать результаты распознавания поз
// с камеры в реальном времени.
//
// ЗАЧЕМ ЭТО НУЖНО: Когда камера снимает видео, эта часть кода позволяет вашему приложению получать
// информацию о найденных позах тела для каждого кадра видео, как только они обнаружены.
//
// КАК ЭТО РАБОТАЕТ: Каждый раз, когда система обрабатывает новый кадр с камеры и находит на нём позы людей,
// она автоматически вызывает определённый метод и передаёт туда результаты - вы можете использовать
// эти данные чтобы отобразить точки на экране или проанализировать положение тела.
protocol PoseLandmarkerServiceLiveStreamDelegate: AnyObject {
  func poseLandmarkerService(_ poseLandmarkerService: PoseLandmarkerService,
                             didFinishDetection result: ResultBundle?,
                             error: Error?)
}

// ЧТО ЭТО: Ещё один протокол, но для работы с видеофайлами (не с камерой в реальном времени).
//
// ЗАЧЕМ ЭТО НУЖНО: Если вы обрабатываете видеофайл, этот протокол позволяет вашему приложению
// отслеживать прогресс обработки (например, чтобы показать пользователю прогресс-бар).
//
// КАК ЭТО РАБОТАЕТ: Система будет сообщать, когда начинается обработка видео и когда
// завершается обработка каждого отдельного кадра видео.
protocol PoseLandmarkerServiceVideoDelegate: AnyObject {
 func poseLandmarkerService(_ poseLandmarkerService: PoseLandmarkerService,
                                  didFinishDetectionOnVideoFrame index: Int)
 func poseLandmarkerService(_ poseLandmarkerService: PoseLandmarkerService,
                             willBeginDetection totalframeCount: Int)
}


// ЧТО ЭТО: Главный класс, который управляет всем процессом распознавания поз людей.
//
// ЗАЧЕМ ЭТО НУЖНО: Этот класс собирает вместе всю логику для настройки и использования
// системы распознавания поз. Он скрывает сложные технические детали и даёт простой способ
// обнаруживать позы на изображениях, видео или с камеры.
//
// КАК ЭТО РАБОТАЕТ: Класс настраивает модель искусственного интеллекта для распознавания поз,
// отправляет изображения на обработку и возвращает результаты с координатами точек тела.
class PoseLandmarkerService: NSObject {

  // Получатель результатов при работе с камерой в реальном времени
  weak var liveStreamDelegate: PoseLandmarkerServiceLiveStreamDelegate?
  
  // Получатель информации о прогрессе обработки видеофайла
  weak var videoDelegate: PoseLandmarkerServiceVideoDelegate?

  // Основной инструмент распознавания поз от MediaPipe
  var poseLandmarker: PoseLandmarker?
  
  // Текущий режим работы: изображение, видео или камера в реальном времени
  private(set) var runningMode = RunningMode.image
  
  // Сколько максимально поз людей искать на одном изображении
  private var numPoses: Int
  
  // Насколько уверена должна быть система, чтобы считать найденное человеком (от 0 до 1)
  private var minPoseDetectionConfidence: Float
  
  // Насколько уверена должна быть система, что нашла все точки тела (от 0 до 1)
  private var minPosePresenceConfidence: Float
  
  // Насколько точно система должна отслеживать движение между кадрами (от 0 до 1)
  private var minTrackingConfidence: Float
  
  // Путь к файлу модели ИИ, которая умеет распознавать позы
  private var modelPath: String
  
  // Устройство, на котором будут выполняться вычисления (CPU или GPU)
  private var delegate: PoseLandmarkerDelegate

  // MARK: - Custom Initializer
  private init?(modelPath: String?,
                runningMode:RunningMode,
                numPoses: Int,
                minPoseDetectionConfidence: Float,
                minPosePresenceConfidence: Float,
                minTrackingConfidence: Float,
                delegate: PoseLandmarkerDelegate) {
    guard let modelPath = modelPath else { return nil }
    self.modelPath = modelPath
    self.runningMode = runningMode
    self.numPoses = numPoses
    self.minPoseDetectionConfidence = minPoseDetectionConfidence
    self.minPosePresenceConfidence = minPosePresenceConfidence
    self.minTrackingConfidence = minTrackingConfidence
    self.delegate = delegate
    super.init()

    createPoseLandmarker()
  }

  // ЧТО ЭТО: Метод, который настраивает и создаёт основной инструмент для распознавания поз
  //
  // ЗАЧЕМ ЭТО НУЖНО: Перед использованием системы распознавания, нужно её правильно настроить
  // с нужными параметрами (точность, количество поз и т.д.)
  //
  // КАК ЭТО РАБОТАЕТ: Метод создаёт новый объект с настройками, задаёт все необходимые параметры
  // и создаёт инструмент распознавания с этими настройками
  private func createPoseLandmarker() {
    // Создаём объект с настройками
    let poseLandmarkerOptions = PoseLandmarkerOptions()
    
    // Задаём режим работы (изображение, видео или камера)
    poseLandmarkerOptions.runningMode = runningMode
    
    // Устанавливаем максимальное количество поз для поиска
    poseLandmarkerOptions.numPoses = numPoses
    
    // Настраиваем пороги точности для разных этапов распознавания
    poseLandmarkerOptions.minPoseDetectionConfidence = minPoseDetectionConfidence
    poseLandmarkerOptions.minPosePresenceConfidence = minPosePresenceConfidence
    poseLandmarkerOptions.minTrackingConfidence = minTrackingConfidence
    
    // Указываем путь к модели ИИ и где выполнять вычисления (CPU/GPU)
    poseLandmarkerOptions.baseOptions.modelAssetPath = modelPath
    poseLandmarkerOptions.baseOptions.delegate = delegate.delegate
    
    // Если используем режим камеры в реальном времени, настраиваем получателя результатов
    if runningMode == .liveStream {
      poseLandmarkerOptions.poseLandmarkerLiveStreamDelegate = self
    }
    
    // Пытаемся создать распознаватель с нашими настройками
    do {
      poseLandmarker = try PoseLandmarker(options: poseLandmarkerOptions)
    }
    catch {
      print(error)
    }
  }

  // MARK: - Static Initializers


  static func liveStreamPoseLandmarkerService(
    modelPath: String?,
    numPoses: Int,
    minPoseDetectionConfidence: Float,
    minPosePresenceConfidence: Float,
    minTrackingConfidence: Float,
    liveStreamDelegate: PoseLandmarkerServiceLiveStreamDelegate?,
    delegate: PoseLandmarkerDelegate) -> PoseLandmarkerService? {
    let poseLandmarkerService = PoseLandmarkerService(
      modelPath: modelPath,
      runningMode: .liveStream,
      numPoses: numPoses,
      minPoseDetectionConfidence: minPoseDetectionConfidence,
      minPosePresenceConfidence: minPosePresenceConfidence,
      minTrackingConfidence: minTrackingConfidence,
      delegate: delegate)
    poseLandmarkerService?.liveStreamDelegate = liveStreamDelegate

    return poseLandmarkerService
  }



  // MARK: - Detection Methods for Different Modes
  


  // ЧТО ЭТО: Метод для распознавания поз на видеопотоке с камеры в реальном времени
  //
  // ЗАЧЕМ ЭТО НУЖНО: Чтобы анализировать каждый кадр с камеры и находить на нём позы людей в реальном времени.
  // Например, для создания приложения, которое реагирует на движения человека перед камерой.
  //
  // КАК ЭТО РАБОТАЕТ: Метод получает кадр с камеры, преобразует его в нужный формат и отправляет на асинхронную
  // обработку (чтобы не тормозить приложение). Результаты приходят через специальный делегат, когда обработка завершена.
  func detectAsync(
    sampleBuffer: CMSampleBuffer,   // Кадр с камеры в формате iOS
    orientation: UIImage.Orientation, // Ориентация устройства (портретная/альбомная)
    timeStamps: Int) {               // Временная метка кадра в миллисекундах
    
    // Преобразуем кадр в формат MediaPipe
    guard let image = try? MPImage(sampleBuffer: sampleBuffer, orientation: orientation) else {
      return
    }
    
    do {
      // Отправляем кадр на асинхронную обработку (чтобы не заставлять приложение ждать)
      // Когда анализ будет готов, результаты придут через делегат liveStreamDelegate
      try poseLandmarker?.detectAsync(image: image, timestampInMilliseconds: timeStamps)
    } catch {
      // Выводим ошибку, если что-то пошло не так
      print(error)
    }
  }






}

// MARK: - PoseLandmarkerLiveStreamDelegate Methods

// ЧТО ЭТО: Реализация протокола, который получает результаты от MediaPipe в режиме реального времени
//
// ЗАЧЕМ ЭТО НУЖНО: Чтобы получать уведомления от MediaPipe, когда анализ кадра завершен
//
// КАК ЭТО РАБОТАЕТ: Когда MediaPipe завершает обработку кадра, она вызывает этот метод,
// а мы передаем результаты дальше в приложение
extension PoseLandmarkerService: PoseLandmarkerLiveStreamDelegate {
    // Этот метод автоматически вызывается MediaPipe, когда завершается анализ кадра
    func poseLandmarker(_ poseLandmarker: PoseLandmarker, didFinishDetection result: PoseLandmarkerResult?, timestampInMilliseconds: Int, error: (any Error)?) {
        // Создаем пакет с результатами и временем обработки
        let resultBundle = ResultBundle(
          inferenceTime: Date().timeIntervalSince1970 * 1000 - Double(timestampInMilliseconds),
          poseLandmarkerResults: [result])
        
        // Передаем результаты в приложение через делегат
        liveStreamDelegate?.poseLandmarkerService(
          self,
          didFinishDetection: resultBundle,
          error: error)
    }
}

// ЧТО ЭТО: Контейнер для хранения результатов распознавания
//
// ЗАЧЕМ ЭТО НУЖНО: Чтобы удобно хранить вместе все важные данные, полученные после распознавания поз
//
// КАК ЭТО РАБОТАЕТ: Структура объединяет информацию о найденных позах, времени распознавания и размере изображения
struct ResultBundle {
  // Время, которое потребовалось на распознавание (в миллисекундах)
  let inferenceTime: Double
  
  // Массив найденных поз (каждая поза содержит точки тела)
  let poseLandmarkerResults: [PoseLandmarkerResult?]
  
  // Размер изображения или видео, на котором выполнялось распознавание
  var size: CGSize = .zero
}
