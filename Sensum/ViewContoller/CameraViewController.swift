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

import AVFoundation
import MediaPipeTasksVision
import UIKit
import os.log

/**
 * The view controller is responsible for performing detection on incoming frames from the live camera and presenting the frames with the
 * landmark of the landmarked poses to the user.
 */
class CameraViewController: UIViewController {
    private struct Constants {
        static let edgeOffset: CGFloat = 2.0
    }
    
    weak var inferenceResultDeliveryDelegate: InferenceResultDeliveryDelegate?
    weak var interfaceUpdatesDelegate: InterfaceUpdatesDelegate?
    
    // Переменные для управления отображением статистики
    private var isStatsVisible = false
    private var fpsLabel: UILabel?
    
    // Переменные для подсчета FPS
    private var frameCount = 0
    private var lastFPSUpdateTime = Date()
    
    // Логгер для системных сообщений
    private let logger = OSLog(subsystem: "com.google.mediapipe.examples.poselandmarker", category: "PoseMetrics")
    
    // Метрики для тестирования точности
    private var jitterValues: [Double] = []
    private var inferenceTimeValues: [Double] = []
    private var visibilityValues: [Double] = []
    private var lastLandmarks: [[NormalizedLandmark]]?
    
    // Программные UI элементы вместо IBOutlets
    var previewView: UIView!
    var cameraUnavailableLabel: UILabel!
    var resumeButton: UIButton!
    var overlayView: OverlayView!
    var metricsLabel: UILabel! // Метка для отображения метрик точности
    var startButton: UIButton! // Кнопка СТАРТ
    
    private var isSessionRunning = false
    private var isObserving = false
    private let backgroundQueue = DispatchQueue(label: "com.google.mediapipe.cameraController.backgroundQueue")
    
    // MARK: Controllers that manage functionality
    // Handles all the camera related functionality
    private var cameraFeedService: CameraFeedService!
    
    private let poseLandmarkerServiceQueue = DispatchQueue(
        label: "com.google.mediapipe.cameraController.poseLandmarkerServiceQueue",
        attributes: .concurrent)
    
    // Queuing reads and writes to poseLandmarkerService using the Apple recommended way
    // as they can be read and written from multiple threads and can result in race conditions.
    private var _poseLandmarkerService: PoseLandmarkerService?
    private var poseLandmarkerService: PoseLandmarkerService? {
        get {
            poseLandmarkerServiceQueue.sync {
                return self._poseLandmarkerService
            }
        }
        set {
            poseLandmarkerServiceQueue.async(flags: .barrier) {
                self._poseLandmarkerService = newValue
            }
        }
    }
    
#if !targetEnvironment(simulator)
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    
    print("!!!!!!! viewWillAppear запущен")
    
    // Сначала создаем все UI элементы
    setupUI()
    
    // Проверка размеров - должны быть не нулевые
    view.layoutIfNeeded() // Форсируем обновление размеров
    print("!!!!!!! Размеры previewView: \(previewView.bounds)")
    
    // Теперь инициализируем камеру, когда уже есть размеры
    cameraFeedService = CameraFeedService(previewView: previewView)
    cameraFeedService.delegate = self
    print("!!!!!!! Создан CameraFeedService в viewWillAppear, previewView.bounds: \(previewView.bounds)")
    
    // Инициализируем модель распознавания
    initializePoseLandmarkerServiceOnSessionResumption()
    
    // Показываем кнопку СТАРТ
    startButton.isHidden = false
    view.bringSubviewToFront(startButton)
    if overlayView != nil {
      overlayView.isHidden = true // Скрываем слой с точками изначально
    }
    
    print("!!!!!!! Все инициализировано корректно")
  }
  
  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    cameraFeedService.stopSession()
    clearPoseLandmarkerServiceOnSessionInterruption()
  }
  
  override func viewDidLoad() {
    super.viewDidLoad()
    
    print("!!!!!!! viewDidLoad запущен")
    
    // Ничего не делаем в viewDidLoad - все будет в viewWillAppear
    print("!!!!!!! Все инициализации перенесены в viewWillAppear")
    
    resetMetrics()
    
  
    
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    
    print("DEBUG: viewDidLoad завершен")
  }
  
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    if cameraFeedService != nil {
      cameraFeedService.updateVideoPreviewLayer(toFrame: previewView.bounds)
    }
  }
  
  override func viewWillLayoutSubviews() {
    super.viewWillLayoutSubviews()
    if cameraFeedService != nil {
      cameraFeedService.updateVideoPreviewLayer(toFrame: previewView.bounds)
    }
  }
  
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    // Важно обновить размер слоя предпросмотра после изменения размеров представления
    if cameraFeedService != nil {
      cameraFeedService.updateVideoPreviewLayer(toFrame: previewView.bounds)
    }
  }
#endif
  
  // Создание и настройка UI элементов
  private func setupUI() {
    view.backgroundColor = .black
    
    // Создание previewView для отображения камеры - во весь экран
    previewView = UIView()
    previewView.layer.cornerRadius = 0
    previewView.clipsToBounds = true
    previewView.backgroundColor = .black
    previewView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(previewView)
    
    print("!!!!!!! SETUP UI: previewView создан")
    
    // Создаем простую кнопку СТАРТ
    startButton = UIButton(type: .system)
    startButton.setTitle("СТАРТ", for: .normal)
    startButton.titleLabel?.font = UIFont.systemFont(ofSize: 24, weight: .heavy) // Увеличенный шрифт
    startButton.backgroundColor = UIColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 1.0) // Ярко-красный фон
    startButton.setTitleColor(.white, for: .normal)
    startButton.layer.cornerRadius = 20
    startButton.layer.borderWidth = 3
    startButton.layer.borderColor = UIColor.white.cgColor
    startButton.translatesAutoresizingMaskIntoConstraints = false
    startButton.addTarget(self, action: #selector(startButtonTapped), for: .touchUpInside)
    view.addSubview(startButton)
    view.bringSubviewToFront(startButton) // Выводим на передний план
    
    print("!!!!!!! SETUP UI: startButton создана и добавлена на вид")
    
    // Создание overlayView для отображения поз
    overlayView = OverlayView()
    overlayView.translatesAutoresizingMaskIntoConstraints = false
    overlayView.contentMode = .scaleAspectFill
    overlayView.backgroundColor = .clear // Устанавливаем прозрачный фон
    overlayView.isHidden = true // Изначально скрываем
    view.addSubview(overlayView)
    
    // Создание надписи о недоступности камеры
    cameraUnavailableLabel = UILabel()
    cameraUnavailableLabel.text = "Камера недоступна"
    cameraUnavailableLabel.textColor = .white
    cameraUnavailableLabel.translatesAutoresizingMaskIntoConstraints = false
    cameraUnavailableLabel.isHidden = true
    view.addSubview(cameraUnavailableLabel)
    
    // Создание кнопки возобновления в стиле Apple
    resumeButton = UIButton(type: .system)
    resumeButton.setTitle("Возобновить", for: .normal)
    resumeButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
    resumeButton.setTitleColor(.white, for: .normal)
    
    // Создаем красивый градиентный фон
    let gradientLayer = CAGradientLayer()
    gradientLayer.colors = [
      UIColor(red: 0.0, green: 0.5, blue: 1.0, alpha: 0.9).cgColor,
      UIColor(red: 0.0, green: 0.7, blue: 0.9, alpha: 0.9).cgColor
    ]
    gradientLayer.locations = [0.0, 1.0]
    gradientLayer.startPoint = CGPoint(x: 0.0, y: 0.0)
    gradientLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
    gradientLayer.cornerRadius = 12
    
    // Создаем контейнер для градиента, так как его нельзя напрямую добавить к кнопке
    let gradientView = UIView()
    gradientView.translatesAutoresizingMaskIntoConstraints = false
    gradientView.layer.addSublayer(gradientLayer)
    gradientView.layer.cornerRadius = 12
    gradientView.clipsToBounds = true
    gradientView.isUserInteractionEnabled = false
    view.addSubview(gradientView)
    
    // Добавляем тень для объемного эффекта
    resumeButton.layer.shadowColor = UIColor.black.cgColor
    resumeButton.layer.shadowOffset = CGSize(width: 0, height: 2)
    resumeButton.layer.shadowRadius = 4
    resumeButton.layer.shadowOpacity = 0.2
    
    resumeButton.layer.cornerRadius = 12
    resumeButton.isHidden = true
    resumeButton.translatesAutoresizingMaskIntoConstraints = false
    resumeButton.addTarget(self, action: #selector(onClickResume(_:)), for: .touchUpInside)
    view.addSubview(resumeButton)
    
    // Установка ограничений для всех элементов
    // Добавляем счетчик FPS для мониторинга производительности
    let fpsLabel = UILabel()
    fpsLabel.text = "0 FPS"
    fpsLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .medium)
    fpsLabel.textColor = .white
    fpsLabel.backgroundColor = UIColor(white: 0.0, alpha: 0.6)
    fpsLabel.layer.cornerRadius = 8
    fpsLabel.layer.masksToBounds = true
    fpsLabel.textAlignment = .center
    fpsLabel.translatesAutoresizingMaskIntoConstraints = false
    fpsLabel.isHidden = true // По умолчанию скрыто
    view.addSubview(fpsLabel)
    self.fpsLabel = fpsLabel
    
    // Добавляем метку для метрик точности
    let metricsLabel = UILabel()
    metricsLabel.text = "Метрики: нет данных"
    metricsLabel.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .medium)
    metricsLabel.textColor = .white
    metricsLabel.backgroundColor = UIColor(white: 0.0, alpha: 0.6)
    metricsLabel.layer.cornerRadius = 8
    metricsLabel.layer.masksToBounds = true
    metricsLabel.textAlignment = .left
    metricsLabel.numberOfLines = 3
    metricsLabel.translatesAutoresizingMaskIntoConstraints = false
    metricsLabel.isHidden = true // По умолчанию скрыто
    view.addSubview(metricsLabel)
    self.metricsLabel = metricsLabel
    
    NSLayoutConstraint.activate([
      // previewView занимает весь экран
      previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      previewView.topAnchor.constraint(equalTo: view.topAnchor),
      previewView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      
      // overlayView такого же размера, как и previewView
      overlayView.leadingAnchor.constraint(equalTo: previewView.leadingAnchor),
      overlayView.trailingAnchor.constraint(equalTo: previewView.trailingAnchor),
      overlayView.topAnchor.constraint(equalTo: previewView.topAnchor),
      overlayView.bottomAnchor.constraint(equalTo: previewView.bottomAnchor),
      
      // Устанавливаем метку по центру
      cameraUnavailableLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      cameraUnavailableLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      
      // Устанавливаем кнопку под меткой
      resumeButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      resumeButton.topAnchor.constraint(equalTo: cameraUnavailableLabel.bottomAnchor, constant: 20),
      resumeButton.widthAnchor.constraint(equalToConstant: 180),
      resumeButton.heightAnchor.constraint(equalToConstant: 48),
      
      // Добавляем ограничения для градиентного фона кнопки
      gradientView.leadingAnchor.constraint(equalTo: resumeButton.leadingAnchor),
      gradientView.trailingAnchor.constraint(equalTo: resumeButton.trailingAnchor),
      gradientView.topAnchor.constraint(equalTo: resumeButton.topAnchor),
      gradientView.bottomAnchor.constraint(equalTo: resumeButton.bottomAnchor),
      
      // Позиционирование элементов интерфейса
      fpsLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      fpsLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
      fpsLabel.heightAnchor.constraint(equalToConstant: 28),
      fpsLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
      
      // Ограничения для кнопки СТАРТ - делаем больше
      startButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      startButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      startButton.widthAnchor.constraint(equalToConstant: 200),
      startButton.heightAnchor.constraint(equalToConstant: 80),
      
      // Ограничения для метки метрик
      metricsLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      metricsLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
      metricsLabel.widthAnchor.constraint(equalToConstant: 200),
      metricsLabel.heightAnchor.constraint(equalToConstant: 60)
    ])
  }
  
  // Resume camera session when click button resume
  @objc func onClickResume(_ sender: Any) {
    cameraFeedService.resumeInterruptedSession {[weak self] isSessionRunning in
      if isSessionRunning {
        self?.resumeButton.isHidden = true
        self?.cameraUnavailableLabel.isHidden = true
        self?.initializePoseLandmarkerServiceOnSessionResumption()
      }
    }
  }

  // Обработчик нажатия на кнопку СТАРТ
  @objc private func startButtonTapped() {
    print("!!!!!!!!!! НАЖАТА КНОПКА СТАРТ !!!!!!!!!")

    // Скрываем кнопку СТАРТ и показываем слой с точками
    startButton.isHidden = true
    overlayView.isHidden = false  // Показываем слой с точками
    
    // Проверяем размеры перед запуском
    print("!!!!!!! Размеры перед запуском: \(previewView.bounds)")
    
    // Запускаем камеру
    cameraFeedService.startLiveCameraSession { [weak self] cameraConfiguration in
      print("!!!!!!! КОНФИГУРАЦИЯ КАМЕРЫ: \(cameraConfiguration)")
      
      DispatchQueue.main.async {
        switch cameraConfiguration {
        case .failed:
          print("!!!!!!! ОШИБКА КАМЕРЫ")
          self?.startButton.isHidden = false
          self?.overlayView.isHidden = true
        case .permissionDenied:
          print("!!!!!!! НЕТ ПРАВ НА КАМЕРУ")
          self?.startButton.isHidden = false
          self?.overlayView.isHidden = true
        case .success:
          print("!!!!!!! КАМЕРА УСПЕШНО ЗАПУЩЕНА")
          // Обновляем размеры слоя предпросмотра после запуска
          self?.cameraFeedService.updateVideoPreviewLayer(toFrame: self?.previewView.bounds ?? .zero)
        }
      }
    }
  }
  
  private func presentCameraPermissionsDeniedAlert() {
    let alertController = UIAlertController(
      title: "Camera Permissions Denied",
      message:
        "Camera permissions have been denied for this app. You can change this by going to Settings",
      preferredStyle: .alert)
    
    let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
    let settingsAction = UIAlertAction(title: "Settings", style: .default) { (action) in
      UIApplication.shared.open(
        URL(string: UIApplication.openSettingsURLString)!, options: [:], completionHandler: nil)
    }
    alertController.addAction(cancelAction)
    alertController.addAction(settingsAction)
    
    present(alertController, animated: true, completion: nil)
  }
  
  private func presentVideoConfigurationErrorAlert() {
    let alert = UIAlertController(
      title: "Camera Configuration Failed",
      message: "There was an error while configuring camera.",
      preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
    
    self.present(alert, animated: true)
  }
  
  @objc private func initializePoseLandmarkerServiceOnSessionResumption() {
    // Предварительно проверяем, что сервис еще не инициализирован
    if poseLandmarkerService != nil {
      print("DEBUG: Модель уже инициализирована")
      return
    }
    
    print("DEBUG: Инициализация модели")
    
    let modelPath = Bundle.main.path(forResource: "pose_landmarker_full", ofType: "task") ?? ""
    let modelName = "Pose Landmarker (Full)"
    
    // Get InferenceConfigurations
    let delegate = InferenceConfigurationManager.sharedInstance.delegate
    let numPoses = InferenceConfigurationManager.sharedInstance.numPoses
    let minDetectionConf = InferenceConfigurationManager.sharedInstance.minPoseDetectionConfidence
    let minPresenceConf = InferenceConfigurationManager.sharedInstance.minPosePresenceConfidence
    let minTrackingConf = InferenceConfigurationManager.sharedInstance.minTrackingConfidence
    
    print("DEBUG: Модель: \(modelPath)")
    
    // Инициализируем сервис распознавания поз
    poseLandmarkerService = PoseLandmarkerService.liveStreamPoseLandmarkerService(
      modelPath: modelPath,
      numPoses: numPoses,
      minPoseDetectionConfidence: minDetectionConf,
      minPosePresenceConfidence: minPresenceConf,
      minTrackingConfidence: minTrackingConf,
      liveStreamDelegate: self,
      delegate: delegate)
      
    startObserveConfigChanges()
  }
  
  private func clearPoseLandmarkerServiceOnSessionInterruption() {
    stopObserveConfigChanges()
    poseLandmarkerService = nil
  }
  
  // Анализ ключевых метрик для конкретного результата распознавания
  private func getCriticalMetrics(result: PoseLandmarkerResult, inferenceTime: Double) -> String? {
    // Логируем подробные метрики только для каждого 30-го кадра (примерно раз в секунду)
    if frameCount % 30 != 0 {
      return nil
    }
    
    guard !result.landmarks.isEmpty, let landmarks = result.landmarks.first else {
      return nil
    }
    
    // Рассчитываем среднюю уверенность для ключевых точек
    var totalVisibility: Float = 0.0
    var countWithVisibility: Int = 0
    for landmark in landmarks {
      if let visibility = landmark.visibility?.floatValue, visibility > 0 {
        totalVisibility += visibility
        countWithVisibility += 1
      }
    }
    
    let avgVisibility = countWithVisibility > 0 ? totalVisibility / Float(countWithVisibility) : 0
    
    // Проверяем наличие ключевых точек тела (плечи, бедра)
    let shoulderIdx = 11 // правое плечо
    let hipIdx = 23      // правое бедро
    
    let shoulderDetected = shoulderIdx < landmarks.count && (landmarks[shoulderIdx].visibility?.floatValue ?? 0) > 0.5
    let hipDetected = hipIdx < landmarks.count && (landmarks[hipIdx].visibility?.floatValue ?? 0) > 0.5
    
    let bodyPartsStatus = "Shoulders: \(shoulderDetected ? "Detected" : "Not detected"), " +
                          "Hips: \(hipDetected ? "Detected" : "Not detected")"
    
    // Формируем метрику стабильности
    let avgJitter = calculateAverageJitter()
    let jitterInfo = avgJitter != nil ? String(format: "Jitter: %.5f", avgJitter!) : "Jitter: N/A"
    
    return "\nFrame \(frameCount) Metrics:\n" +
           "Inference time: \(String(format: "%.2f", inferenceTime)) ms, " +
           "Average visibility: \(String(format: "%.2f", avgVisibility))\n" +
           "\(bodyPartsStatus)\n" +
           "\(jitterInfo)"
  }
  
  // Переключатель отображения статистики
  @objc private func toggleStatsDisplay() {
    isStatsVisible = !isStatsVisible
    fpsLabel?.isHidden = !isStatsVisible
    metricsLabel?.isHidden = !isStatsVisible
    
    // Анимируем изменение, чтобы привлечь внимание
    UIView.animate(withDuration: 0.3) { [weak self] in
      self?.fpsLabel?.alpha = self?.isStatsVisible == true ? 1.0 : 0.0
      self?.metricsLabel?.alpha = self?.isStatsVisible == true ? 1.0 : 0.0
    }
  }
  
  // MARK: - Методы системы метрик
  
  /// Сбрасывает все накопленные метрики
  private func resetMetrics() {
    jitterValues.removeAll()
    inferenceTimeValues.removeAll()
    visibilityValues.removeAll()
    lastLandmarks = nil
  }
  
  /// Обновляет метрики с новыми данными
  /// - Parameters:
  ///   - landmarks: Массив ключевых точек
  ///   - inferenceTime: Время выполнения инференса
  private func updateMetrics(landmarks: [[NormalizedLandmark]], inferenceTime: Double) {
    // Добавляем время инференса
    inferenceTimeValues.append(inferenceTime)
    // Ограничиваем количество сохраняемых значений
    if inferenceTimeValues.count > 100 {
      inferenceTimeValues.removeFirst()
    }
    
    // Рассчитываем jitter при наличии предыдущих точек
    if let previousLandmarks = lastLandmarks, !landmarks.isEmpty, !previousLandmarks.isEmpty {
      let jitter = calculateJitter(previous: previousLandmarks.first!, current: landmarks.first!)
      jitterValues.append(jitter)
      
      // Ограничиваем количество сохраняемых значений
      if jitterValues.count > 30 {
        jitterValues.removeFirst()
      }
    }
    
    // Сохраняем текущие точки для следующего сравнения
    lastLandmarks = landmarks
    
    // Считаем среднюю видимость точек
    if !landmarks.isEmpty, let firstPose = landmarks.first {
      var totalVisibility: Double = 0.0
      var countWithVisibility: Int = 0
      
      for landmark in firstPose {
        if let visibility = landmark.visibility?.floatValue {
          totalVisibility += Double(visibility)
          countWithVisibility += 1
        }
      }
      
      if countWithVisibility > 0 {
        let avgVisibility = totalVisibility / Double(countWithVisibility)
        visibilityValues.append(avgVisibility)
        
        // Ограничиваем количество сохраняемых значений
        if visibilityValues.count > 30 {
          visibilityValues.removeFirst()
        }
      }
    }
  }
  
  /// Рассчитывает коэффициент дрожания (jitter) между двумя наборами точек
  /// - Parameters:
  ///   - previous: Предыдущие точки
  ///   - current: Текущие точки
  /// - Returns: Коэффициент дрожания
  private func calculateJitter(previous: [NormalizedLandmark], current: [NormalizedLandmark]) -> Double {
    guard previous.count == current.count, !previous.isEmpty else {
      return 0.0
    }
    
    var totalJitter: Double = 0.0
    var validPoints = 0
    
    for i in 0..<min(previous.count, current.count) {
      // Учитываем только точки с высокой видимостью
      if let prevVisibility = previous[i].visibility?.floatValue, let currVisibility = current[i].visibility?.floatValue,
         prevVisibility > 0.5, currVisibility > 0.5 {
        
        let dx = Double(current[i].x - previous[i].x)
        let dy = Double(current[i].y - previous[i].y)
        let dz = Double(current[i].z - previous[i].z)
        
        // Евклидово расстояние между точками
        let distance = sqrt(dx*dx + dy*dy + dz*dz)
        totalJitter += distance
        validPoints += 1
      }
    }
    
    return validPoints > 0 ? totalJitter / Double(validPoints) : 0.0
  }
  
  /// Рассчитывает средний коэффициент дрожания за последние кадры
  /// - Returns: Средний коэффициент дрожания или nil, если нет данных
  private func calculateAverageJitter() -> Double? {
    guard !jitterValues.isEmpty else {
      return nil
    }
    return jitterValues.reduce(0, +) / Double(jitterValues.count)
  }
  
  private func startObserveConfigChanges() {
    NotificationCenter.default
      .addObserver(self,
                   selector: #selector(observeConfigUpdate),
                   name: InferenceConfigurationManager.notificationName,
                   object: nil)
    isObserving = true
  }
  
  private func stopObserveConfigChanges() {
    if isObserving {
      NotificationCenter.default
        .removeObserver(self,
                        name:InferenceConfigurationManager.notificationName,
                        object: nil)
    }
    isObserving = false
  }
  
  @objc private func observeConfigUpdate() {
    // Сбрасываем и создаем сервис заново
    poseLandmarkerService = nil
    initializePoseLandmarkerServiceOnSessionResumption()
  }
}

extension CameraViewController: CameraFeedServiceDelegate {
  
  func didOutput(sampleBuffer: CMSampleBuffer, orientation: UIImage.Orientation) {
    let currentTimeMs = Date().timeIntervalSince1970 * 1000
    
    // Обновляем счетчик FPS (раз в секунду)
    frameCount += 1
    let now = Date()
    let elapsed = now.timeIntervalSince(lastFPSUpdateTime)
    
    if (elapsed >= 1.0) {
      let fps = Double(frameCount) / elapsed
      DispatchQueue.main.async { [weak self] in
        if let self = self, self.isStatsVisible {
          self.fpsLabel?.text = String(format: "%.1f FPS", fps)
        }
      }
      frameCount = 0
      lastFPSUpdateTime = now
    }
    
    // Pass the pixel buffer to mediapipe
    backgroundQueue.async { [weak self] in
      self?.poseLandmarkerService?.detectAsync(
        sampleBuffer: sampleBuffer,
        orientation: orientation,
        timeStamps: Int(currentTimeMs))
    }
  }
  
  // MARK: Session Handling Alerts
  func sessionWasInterrupted(canResumeManually resumeManually: Bool) {
    // Updates the UI when session is interupted.
    if resumeManually {
      resumeButton.isHidden = false
      startButton.isHidden = true
    } else {
      cameraUnavailableLabel.isHidden = false
      startButton.isHidden = true
    }
    clearPoseLandmarkerServiceOnSessionInterruption()
  }
  
  func sessionInterruptionEnded() {
    // Updates UI once session interruption has ended.
    cameraUnavailableLabel.isHidden = true
    resumeButton.isHidden = true
    startButton.isHidden = false  // Показываем кнопку СТАРТ снова
    initializePoseLandmarkerServiceOnSessionResumption()
  }
  
  func didEncounterSessionRuntimeError() {
    // Handles session run time error by updating the UI and providing a button if session can be
    // manually resumed.
    resumeButton.isHidden = false
    startButton.isHidden = true  // Скрываем кнопку СТАРТ при ошибке
    clearPoseLandmarkerServiceOnSessionInterruption()
  }
}

// MARK: PoseLandmarkerServiceLiveStreamDelegate
extension CameraViewController: PoseLandmarkerServiceLiveStreamDelegate {
    func poseLandmarkerService(
        _ poseLandmarkerService: PoseLandmarkerService,
        didFinishDetection result: ResultBundle?,
        error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let weakSelf = self else { return }
            weakSelf.inferenceResultDeliveryDelegate?.didPerformInference(result: result)
            guard let poseLandmarkerResult = result?.poseLandmarkerResults.first as? PoseLandmarkerResult else { return }
            
            // Анализ углов для каждой найденной позы
            for landmarks in poseLandmarkerResult.landmarks {
                // Перемещаем отдельные точки в массив
                let landmarksArray = Array(landmarks)
                
                // Обновляем метрики с учетом углов
                if let inferenceTime = result?.inferenceTime {
                    // Получаем углы (теперь не используем if let, так как метод всегда возвращает словарь)
                    let angles = PoseAnalyzer.analyzePose(landmarks: landmarksArray)
                    
                    // Логируем углы для отладки
                    os_log("Pose angles: %{public}@", log: weakSelf.logger, type: .debug, String(describing: angles))
                    
                    // Обновляем метрики
                    weakSelf.updateMetricsWithAngles(landmarks: landmarksArray, angles: angles, inferenceTime: inferenceTime)
                }
            }
            
            let imageSize = weakSelf.cameraFeedService.videoResolution
            let poseOverlays = OverlayView.poseOverlays(
                fromMultiplePoseLandmarks: poseLandmarkerResult.landmarks,
                inferredOnImageOfSize: imageSize,
                ovelayViewSize: weakSelf.overlayView.bounds.size,
                imageContentMode: weakSelf.overlayView.imageContentMode,
                andOrientation: UIImage.Orientation.from(
                    deviceOrientation: UIDevice.current.orientation))
            
            weakSelf.overlayView.draw(
                poseOverlays: poseOverlays,
                inBoundsOfContentImageOfSize: imageSize,
                imageContentMode: weakSelf.cameraFeedService.videoGravity.contentMode)
        }
    }
}

extension CameraViewController {
    private func updateMetricsWithAngles(landmarks: [NormalizedLandmark], angles: [String: Double], inferenceTime: Double) {
        // Создаем новый массив из массива точек
        let landmarksArray = [landmarks]
        
        // Обновляем базовые метрики
        updateMetrics(landmarks: landmarksArray, inferenceTime: inferenceTime)
        
        // Добавляем информацию об углах в метрики
        if self.isStatsVisible {
            let angleText = String(format: "\nE: %.1f/%.1f K: %.1f/%.1f",
                                 angles["leftElbow"] ?? 0,
                                 angles["rightElbow"] ?? 0,
                                 angles["leftKnee"] ?? 0,
                                 angles["rightKnee"] ?? 0)
            
            self.metricsLabel?.text = (self.metricsLabel?.text ?? "") + angleText
        }
    }
}

// MARK: - AVLayerVideoGravity Extension
extension AVLayerVideoGravity {
  var contentMode: UIView.ContentMode {
    switch self {
    case .resizeAspectFill:
      return .scaleAspectFill
    case .resizeAspect:
      return .scaleAspectFit
    case .resize:
      return .scaleToFill
    default:
      return .scaleAspectFill
    }
  }
}
