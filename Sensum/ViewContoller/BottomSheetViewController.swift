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

import UIKit

protocol BottomSheetViewControllerDelegate: AnyObject {
  /**
   This method is called when the user opens or closes the bottom sheet.
  **/
  func viewController(
    _ viewController: BottomSheetViewController,
    didSwitchBottomSheetViewState isOpen: Bool)
}

/** The view controller is responsible for presenting the controls to change the meta data for the pose landmarker and updating the singleton`` DetectorMetadata`` on user input.
 */
class BottomSheetViewController: UIViewController {

  // MARK: Delegates
  weak var delegate: BottomSheetViewControllerDelegate?

  // MARK: UI Компоненты
  var inferenceTimeNameLabel: UILabel!
  var inferenceTimeLabel: UILabel!

  var numPosesStepper: UIStepper!
  var numPosesValueLabel: UILabel!
  var minPoseDetectionConfidenceStepper: UIStepper!
  var minPoseDetectionConfidenceValueLabel: UILabel!
  var minPosePresenceConfidenceStepper: UIStepper!
  var minPosePresenceConfidenceValueLabel: UILabel!
  var minTrackingConfidenceStepper: UIStepper!
  var minTrackingConfidenceValueLabel: UILabel!
  // Выбор модели больше не нужен, так как используется только Full модель

  var toggleBottomSheetButton: UIButton!
  var chooseDelegateButton: UIButton!

  // MARK: Instance Variables
  var isUIEnabled: Bool = false {
    didSet {
      enableOrDisableClicks()
    }
  }
  
  override func viewDidLoad() {
    super.viewDidLoad()
    createUI()
    setupUI()
    enableOrDisableClicks()
  }
  
  // MARK: - Public Functions
  func update(inferenceTimeString: String) {
    inferenceTimeLabel.text = inferenceTimeString
  }

  // MARK: - Private function
  private func createUI() {
    // Фон с эффектом матового стекла (как в iOS Control Center)
    let blurEffect = UIBlurEffect(style: .systemThinMaterial)
    let blurView = UIVisualEffectView(effect: blurEffect)
    blurView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(blurView)
    
    NSLayoutConstraint.activate([
      blurView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      blurView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      blurView.topAnchor.constraint(equalTo: view.topAnchor),
      blurView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
    ])
    
    // Добавляем разделитель в верхней части (индикатор перетаскивания)
    let dragIndicator = UIView()
    dragIndicator.backgroundColor = UIColor.systemGray3
    dragIndicator.layer.cornerRadius = 2.5
    dragIndicator.translatesAutoresizingMaskIntoConstraints = false
    blurView.contentView.addSubview(dragIndicator)
    
    // Создаем заголовок для времени вывода
    inferenceTimeNameLabel = UILabel()
    inferenceTimeNameLabel.text = "Время вывода:"
    inferenceTimeNameLabel.font = UIFont.systemFont(ofSize: 15, weight: .medium)
    inferenceTimeNameLabel.textColor = .label
    inferenceTimeNameLabel.translatesAutoresizingMaskIntoConstraints = false
    inferenceTimeNameLabel.isHidden = true
    blurView.contentView.addSubview(inferenceTimeNameLabel)
    
    inferenceTimeLabel = UILabel()
    inferenceTimeLabel.text = "0ms"
    inferenceTimeLabel.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
    inferenceTimeLabel.textColor = .secondaryLabel
    inferenceTimeLabel.translatesAutoresizingMaskIntoConstraints = false
    inferenceTimeLabel.isHidden = true
    blurView.contentView.addSubview(inferenceTimeLabel)
    
    // Создаем надписи и элементы управления
    let createLabel = { (text: String) -> UILabel in
      let label = UILabel()
      label.text = text
      label.font = UIFont.systemFont(ofSize: 15, weight: .medium)
      label.textColor = .label
      label.translatesAutoresizingMaskIntoConstraints = false
      return label
    }
    
    let numPosesLabel = createLabel("Количество поз:")
    blurView.contentView.addSubview(numPosesLabel)
    
    numPosesStepper = UIStepper()
    numPosesStepper.minimumValue = 1
    numPosesStepper.maximumValue = 10
    numPosesStepper.stepValue = 1
    numPosesStepper.translatesAutoresizingMaskIntoConstraints = false
    numPosesStepper.addTarget(self, action: #selector(numPosesStepperValueChanged(_:)), for: .valueChanged)
    blurView.contentView.addSubview(numPosesStepper)
    
    numPosesValueLabel = createLabel("1")
    blurView.contentView.addSubview(numPosesValueLabel)
    
    let minPoseDetectionLabel = createLabel("Мин. уровень уверенности обнаружения:")
    blurView.contentView.addSubview(minPoseDetectionLabel)
    
    minPoseDetectionConfidenceStepper = UIStepper()
    minPoseDetectionConfidenceStepper.minimumValue = 0.0
    minPoseDetectionConfidenceStepper.maximumValue = 1.0
    minPoseDetectionConfidenceStepper.stepValue = 0.1
    minPoseDetectionConfidenceStepper.translatesAutoresizingMaskIntoConstraints = false
    minPoseDetectionConfidenceStepper.addTarget(self, action: #selector(minPoseDetectionConfidenceStepperValueChanged(_:)), for: .valueChanged)
    blurView.contentView.addSubview(minPoseDetectionConfidenceStepper)
    
    minPoseDetectionConfidenceValueLabel = createLabel("0.5")
    blurView.contentView.addSubview(minPoseDetectionConfidenceValueLabel)
    
    let minPosePresenceLabel = createLabel("Мин. уровень уверенности присутствия:")
    blurView.contentView.addSubview(minPosePresenceLabel)
    
    minPosePresenceConfidenceStepper = UIStepper()
    minPosePresenceConfidenceStepper.minimumValue = 0.0
    minPosePresenceConfidenceStepper.maximumValue = 1.0
    minPosePresenceConfidenceStepper.stepValue = 0.1
    minPosePresenceConfidenceStepper.translatesAutoresizingMaskIntoConstraints = false
    minPosePresenceConfidenceStepper.addTarget(self, action: #selector(minPosePresenceConfidenceStepperValueChanged(_:)), for: .valueChanged)
    blurView.contentView.addSubview(minPosePresenceConfidenceStepper)
    
    minPosePresenceConfidenceValueLabel = createLabel("0.5")
    blurView.contentView.addSubview(minPosePresenceConfidenceValueLabel)
    
    let minTrackingLabel = createLabel("Мин. уровень уверенности отслеживания:")
    blurView.contentView.addSubview(minTrackingLabel)
    
    minTrackingConfidenceStepper = UIStepper()
    minTrackingConfidenceStepper.minimumValue = 0.0
    minTrackingConfidenceStepper.maximumValue = 1.0
    minTrackingConfidenceStepper.stepValue = 0.1
    minTrackingConfidenceStepper.translatesAutoresizingMaskIntoConstraints = false
    minTrackingConfidenceStepper.addTarget(self, action: #selector(minTrackingConfidenceStepperValueChanged(_:)), for: .valueChanged)
    blurView.contentView.addSubview(minTrackingConfidenceStepper)
    
    minTrackingConfidenceValueLabel = createLabel("0.5")
    blurView.contentView.addSubview(minTrackingConfidenceValueLabel)
    
    // Создаем кнопку для выбора delegate
    chooseDelegateButton = UIButton(type: .system)
    chooseDelegateButton.setTitle("CPU", for: .normal)
    chooseDelegateButton.translatesAutoresizingMaskIntoConstraints = false
    blurView.contentView.addSubview(chooseDelegateButton)
    
    // Кнопка сворачивания/разворачивания панели в стиле iOS
    toggleBottomSheetButton = UIButton(type: .system)
    toggleBottomSheetButton.setImage(UIImage(systemName: "chevron.up"), for: .normal)
    toggleBottomSheetButton.setTitle("Настройки", for: .normal)
    toggleBottomSheetButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
    
    // Добавление стиля для кнопки с поддержкой тёмной темы
    if #available(iOS 13.0, *) {
      toggleBottomSheetButton.setTitleColor(.systemBlue, for: .normal)
      toggleBottomSheetButton.tintColor = .systemBlue
    } else {
      toggleBottomSheetButton.setTitleColor(.blue, for: .normal)
      toggleBottomSheetButton.tintColor = .blue
    }
    
    // Добавление полупрозрачного фона
    toggleBottomSheetButton.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.8)
    toggleBottomSheetButton.layer.cornerRadius = 16
    
    // Добавление тени для эффекта парения
    toggleBottomSheetButton.layer.shadowColor = UIColor.black.cgColor
    toggleBottomSheetButton.layer.shadowOffset = CGSize(width: 0, height: 2)
    toggleBottomSheetButton.layer.shadowRadius = 4
    toggleBottomSheetButton.layer.shadowOpacity = 0.1
    
    toggleBottomSheetButton.translatesAutoresizingMaskIntoConstraints = false
    toggleBottomSheetButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
    toggleBottomSheetButton.addTarget(self, action: #selector(expandButtonTouchUpInside(_:)), for: .touchUpInside)
    blurView.contentView.addSubview(toggleBottomSheetButton)
    
    // Устанавливаем constraint для индикатора перетаскивания
    NSLayoutConstraint.activate([
      dragIndicator.widthAnchor.constraint(equalToConstant: 36),
      dragIndicator.heightAnchor.constraint(equalToConstant: 5),
      dragIndicator.centerXAnchor.constraint(equalTo: blurView.contentView.centerXAnchor),
      dragIndicator.topAnchor.constraint(equalTo: blurView.contentView.topAnchor, constant: 8)
    ])
    
    // Устанавливаем constraints для всех элементов
    NSLayoutConstraint.activate([
      toggleBottomSheetButton.topAnchor.constraint(equalTo: dragIndicator.bottomAnchor, constant: 8),
      toggleBottomSheetButton.centerXAnchor.constraint(equalTo: blurView.contentView.centerXAnchor),
      
      inferenceTimeNameLabel.topAnchor.constraint(equalTo: toggleBottomSheetButton.bottomAnchor, constant: 24),
      inferenceTimeNameLabel.leadingAnchor.constraint(equalTo: blurView.contentView.leadingAnchor, constant: 24),
      
      inferenceTimeLabel.topAnchor.constraint(equalTo: inferenceTimeNameLabel.topAnchor),
      inferenceTimeLabel.leadingAnchor.constraint(equalTo: inferenceTimeNameLabel.trailingAnchor, constant: 10),
      
      numPosesLabel.topAnchor.constraint(equalTo: inferenceTimeNameLabel.bottomAnchor, constant: 24),
      numPosesLabel.leadingAnchor.constraint(equalTo: blurView.contentView.leadingAnchor, constant: 24),
      
      numPosesStepper.topAnchor.constraint(equalTo: numPosesLabel.topAnchor),
      numPosesStepper.trailingAnchor.constraint(equalTo: blurView.contentView.trailingAnchor, constant: -24),
      
      numPosesValueLabel.centerYAnchor.constraint(equalTo: numPosesStepper.centerYAnchor),
      numPosesValueLabel.trailingAnchor.constraint(equalTo: numPosesStepper.leadingAnchor, constant: -12),
      
      minPoseDetectionLabel.topAnchor.constraint(equalTo: numPosesLabel.bottomAnchor, constant: 24),
      minPoseDetectionLabel.leadingAnchor.constraint(equalTo: blurView.contentView.leadingAnchor, constant: 24),
      
      minPoseDetectionConfidenceStepper.topAnchor.constraint(equalTo: minPoseDetectionLabel.bottomAnchor, constant: 8),
      minPoseDetectionConfidenceStepper.trailingAnchor.constraint(equalTo: blurView.contentView.trailingAnchor, constant: -24),
      
      minPoseDetectionConfidenceValueLabel.centerYAnchor.constraint(equalTo: minPoseDetectionConfidenceStepper.centerYAnchor),
      minPoseDetectionConfidenceValueLabel.trailingAnchor.constraint(equalTo: minPoseDetectionConfidenceStepper.leadingAnchor, constant: -10),
      
      minPosePresenceLabel.topAnchor.constraint(equalTo: minPoseDetectionConfidenceStepper.bottomAnchor, constant: 24),
      minPosePresenceLabel.leadingAnchor.constraint(equalTo: blurView.contentView.leadingAnchor, constant: 24),
      
      minPosePresenceConfidenceStepper.topAnchor.constraint(equalTo: minPosePresenceLabel.bottomAnchor, constant: 8),
      minPosePresenceConfidenceStepper.trailingAnchor.constraint(equalTo: blurView.contentView.trailingAnchor, constant: -24),
      
      minPosePresenceConfidenceValueLabel.centerYAnchor.constraint(equalTo: minPosePresenceConfidenceStepper.centerYAnchor),
      minPosePresenceConfidenceValueLabel.trailingAnchor.constraint(equalTo: minPosePresenceConfidenceStepper.leadingAnchor, constant: -10),
      
      minTrackingLabel.topAnchor.constraint(equalTo: minPosePresenceConfidenceStepper.bottomAnchor, constant: 24),
      minTrackingLabel.leadingAnchor.constraint(equalTo: blurView.contentView.leadingAnchor, constant: 24),
      
      minTrackingConfidenceStepper.topAnchor.constraint(equalTo: minTrackingLabel.bottomAnchor, constant: 8),
      minTrackingConfidenceStepper.trailingAnchor.constraint(equalTo: blurView.contentView.trailingAnchor, constant: -24),
      
      minTrackingConfidenceValueLabel.centerYAnchor.constraint(equalTo: minTrackingConfidenceStepper.centerYAnchor),
      minTrackingConfidenceValueLabel.trailingAnchor.constraint(equalTo: minTrackingConfidenceStepper.leadingAnchor, constant: -10),
      
      chooseDelegateButton.topAnchor.constraint(equalTo: minTrackingConfidenceStepper.bottomAnchor, constant: 24),
      chooseDelegateButton.centerXAnchor.constraint(equalTo: blurView.contentView.centerXAnchor)
    ])
  }
  
  private func setupUI() {
    numPosesStepper.value = Double(InferenceConfigurationManager.sharedInstance.numPoses)
    numPosesValueLabel.text = "\(InferenceConfigurationManager.sharedInstance.numPoses)"

    minPoseDetectionConfidenceStepper.value = Double(InferenceConfigurationManager.sharedInstance.minPoseDetectionConfidence)
    minPoseDetectionConfidenceValueLabel.text = "\(InferenceConfigurationManager.sharedInstance.minPoseDetectionConfidence)"

    minPosePresenceConfidenceStepper.value = Double(InferenceConfigurationManager.sharedInstance.minPosePresenceConfidence)
    minPosePresenceConfidenceValueLabel.text = "\(InferenceConfigurationManager.sharedInstance.minPosePresenceConfidence)"

    minTrackingConfidenceStepper.value = Double(InferenceConfigurationManager.sharedInstance.minTrackingConfidence)
    minTrackingConfidenceValueLabel.text = "\(InferenceConfigurationManager.sharedInstance.minTrackingConfidence)"

    let selectedDelegateAction = {(action: UIAction) in
      self.updateDelegate(title: action.title)
    }
    let delegateActions: [UIAction] = PoseLandmarkerDelegate.allCases.compactMap { delegate in
      return UIAction(
        title: delegate.name,
        state: (InferenceConfigurationManager.sharedInstance.delegate == delegate) ? .on : .off,
        handler: selectedDelegateAction
      )
    }

    chooseDelegateButton.menu = UIMenu(children: delegateActions)
    chooseDelegateButton.showsMenuAsPrimaryAction = true
    chooseDelegateButton.changesSelectionAsPrimaryAction = true
    chooseDelegateButton.setTitle(InferenceConfigurationManager.sharedInstance.delegate.name, for: .normal)
  }
  
  private func enableOrDisableClicks() {
    numPosesStepper.isEnabled = isUIEnabled
    minPoseDetectionConfidenceStepper.isEnabled = isUIEnabled
    minPosePresenceConfidenceStepper.isEnabled = isUIEnabled
    minTrackingConfidenceStepper.isEnabled = isUIEnabled
  }

  // Выбор модели больше не нужен, так как используется только Full модель

  private func updateDelegate(title: String) {
    guard let delegate = PoseLandmarkerDelegate(name: title) else { return }
    InferenceConfigurationManager.sharedInstance.delegate = delegate
  }

  // MARK: IBAction
  @objc func expandButtonTouchUpInside(_ sender: UIButton) {
    sender.isSelected.toggle()
    toggleButtonUI(isExpanded: sender.isSelected)
    delegate?.viewController(self, didSwitchBottomSheetViewState: sender.isSelected)
  }
  
  /// Обновляет интерфейс кнопки и панели в зависимости от состояния развернутости
  func toggleButtonUI(isExpanded: Bool) {
    // Показываем/скрываем время вывода
    inferenceTimeLabel.isHidden = !isExpanded
    inferenceTimeNameLabel.isHidden = !isExpanded
    
    // Обновляем иконку и текст кнопки
    let imageName = isExpanded ? "chevron.down" : "chevron.up"
    let buttonTitle = isExpanded ? "Готово" : "Настройки"
    
    // Устанавливаем новые значения с анимацией
    UIView.transition(with: toggleBottomSheetButton, duration: 0.3, options: .transitionCrossDissolve, animations: {
      self.toggleBottomSheetButton.setImage(UIImage(systemName: imageName), for: .normal)
      self.toggleBottomSheetButton.setTitle(buttonTitle, for: .normal)
    }, completion: nil)
  }

  @objc func numPosesStepperValueChanged(_ sender: UIStepper) {
    let numPoses = Int(sender.value)
    InferenceConfigurationManager.sharedInstance.numPoses = numPoses
    numPosesValueLabel.text = "\(numPoses)"
  }

  @objc func minPoseDetectionConfidenceStepperValueChanged(_ sender: UIStepper) {
    let minPoseDetectionConfidence = Float(sender.value)
    InferenceConfigurationManager.sharedInstance.minPoseDetectionConfidence = minPoseDetectionConfidence
    minPoseDetectionConfidenceValueLabel.text = "\(minPoseDetectionConfidence)"
  }

  @objc func minPosePresenceConfidenceStepperValueChanged(_ sender: UIStepper) {
    let minPosePresenceConfidence = Float(sender.value)
    InferenceConfigurationManager.sharedInstance.minPosePresenceConfidence = minPosePresenceConfidence
    minPosePresenceConfidenceValueLabel.text = "\(minPosePresenceConfidence)"
  }

  @objc func minTrackingConfidenceStepperValueChanged(_ sender: UIStepper) {
    let minTrackingConfidence = Float(sender.value)
    InferenceConfigurationManager.sharedInstance.minTrackingConfidence = minTrackingConfidence
    minTrackingConfidenceValueLabel.text = "\(minTrackingConfidence)"
  }
}
