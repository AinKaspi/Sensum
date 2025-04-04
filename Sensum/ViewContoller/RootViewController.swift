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

protocol InferenceResultDeliveryDelegate: AnyObject {
  func didPerformInference(result: ResultBundle?)
}

protocol InterfaceUpdatesDelegate: AnyObject {
  func shouldClicksBeEnabled(_ isEnabled: Bool)
}

/** 
  * The view controller is responsible for handling the camera feed and presenting the inferenceVC.
  */
class RootViewController: UIViewController {

  // MARK: Программные UI элементы
  private var containerView: UIView!
  private var bottomSheetView: UIView!
  private var bottomSheetViewBottomSpace: NSLayoutConstraint!
  private var bottomViewHeightConstraint: NSLayoutConstraint!
  
  // MARK: Constants
  private struct Constants {
    // Полностью скрываем панель настроек
    static let inferenceBottomHeight = 0.0
    static let expandButtonHeight = 0.0
    static let expandButtonTopSpace = 0.0
    // Панель всегда скрыта
    static let showPanelByDefault = false
  }
  
  // MARK: Controllers that manage functionality
  private var inferenceViewController: BottomSheetViewController?
  private var cameraViewController: CameraViewController?
  // mediaLibraryViewController удален, т.к. оставляем только камеру
  
  // MARK: Private Instance Variables
  private var totalBottomSheetHeight: CGFloat {
    guard let isOpen = inferenceViewController?.toggleBottomSheetButton.isSelected else {
      return 0.0
    }
    
    return isOpen ? Constants.inferenceBottomHeight - self.view.safeAreaInsets.bottom
      : Constants.expandButtonHeight + Constants.expandButtonTopSpace
  }

  // MARK: View Handling Methods
  override func viewDidLoad() {
    super.viewDidLoad()
    
    setupUI()
    // Удаляем создание панели настроек
    // createBottomSheetViewController()
    createCameraViewController()
  }
  
  override func viewWillLayoutSubviews() {
    super.viewWillLayoutSubviews()
    
    guard inferenceViewController?.toggleBottomSheetButton.isSelected == true else {
      bottomSheetViewBottomSpace.constant = -Constants.inferenceBottomHeight
      + Constants.expandButtonHeight
      + self.view.safeAreaInsets.bottom
      + Constants.expandButtonTopSpace
      return
    }
    
    bottomSheetViewBottomSpace.constant = 0.0
  }
  
  override var preferredStatusBarStyle: UIStatusBarStyle {
    return .lightContent
  }
  
  // MARK: UI Setup
  private func setupUI() {
    view.backgroundColor = .black
    
    // Создаем контейнер для камеры, который занимает весь экран
    containerView = UIView()
    containerView.translatesAutoresizingMaskIntoConstraints = false
    containerView.backgroundColor = .black // Добавляем черный фон
    view.addSubview(containerView)
    
    // Удаляем нижнюю панель
    bottomSheetView = UIView() // Создаем пустую панель для совместимости
    bottomSheetView.translatesAutoresizingMaskIntoConstraints = false
    bottomSheetView.backgroundColor = .clear // Делаем прозрачной
    bottomSheetView.isHidden = true // Скрываем полностью
    view.addSubview(bottomSheetView)
    
    // Создаем минимальные constraints для пустой панели
    bottomViewHeightConstraint = bottomSheetView.heightAnchor.constraint(equalToConstant: 0)
    bottomSheetViewBottomSpace = bottomSheetView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 0)
    
    // Контейнер для камеры теперь занимает весь экран
    NSLayoutConstraint.activate([
      containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      containerView.topAnchor.constraint(equalTo: view.topAnchor),
      containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      
      // Минимальные ограничения для пустой панели
      bottomSheetView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      bottomSheetView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      bottomViewHeightConstraint,
      bottomSheetViewBottomSpace
    ])
  }
  
  // MARK: View Controllers Setup
  private func createBottomSheetViewController() {
    // Полностью удаляем панель настроек
    // Пустой метод, чтобы не создавать панель вообще
  }
  
  private func createCameraViewController() {
    cameraViewController = CameraViewController()
    cameraViewController?.inferenceResultDeliveryDelegate = self
    cameraViewController?.interfaceUpdatesDelegate = self
    
    if let cameraVC = cameraViewController {
      addCameraViewController(cameraVC)
    }
  }
  
  // Методы для работы с MediaLibrary удалены
}

// Методы добавления контроллеров на экран
extension RootViewController {
  /**
   * Добавляет контроллер камеры на главный экран
   */
  func addCameraViewController(_ cameraVC: CameraViewController) {
    addChild(cameraVC)
    cameraVC.view.translatesAutoresizingMaskIntoConstraints = false
    containerView.addSubview(cameraVC.view)
    
    NSLayoutConstraint.activate([
      cameraVC.view.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
      cameraVC.view.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
      cameraVC.view.topAnchor.constraint(equalTo: containerView.topAnchor),
      cameraVC.view.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
    ])
    
    cameraVC.didMove(toParent: self)
    self.shouldClicksBeEnabled(true)
  }
}

// MARK: InferenceResultDeliveryDelegate Methods
extension RootViewController: InferenceResultDeliveryDelegate {
  func didPerformInference(result: ResultBundle?) {
    var inferenceTimeString = ""
    
    if let inferenceTime = result?.inferenceTime {
      inferenceTimeString = String(format: "%.2fms", inferenceTime)
    }
    inferenceViewController?.update(inferenceTimeString: inferenceTimeString)
  }
}

// MARK: InterfaceUpdatesDelegate Methods
extension RootViewController: InterfaceUpdatesDelegate {
  func shouldClicksBeEnabled(_ isEnabled: Bool) {
    inferenceViewController?.isUIEnabled = isEnabled
  }
}

// MARK: InferenceViewControllerDelegate Methods
extension RootViewController: BottomSheetViewControllerDelegate {
  func viewController(
    _ viewController: BottomSheetViewController,
    didSwitchBottomSheetViewState isOpen: Bool) {
      if isOpen == true {
        bottomSheetViewBottomSpace.constant = 0.0
      }
      else {
        bottomSheetViewBottomSpace.constant = -Constants.inferenceBottomHeight
        + Constants.expandButtonHeight
        + self.view.safeAreaInsets.bottom
        + Constants.expandButtonTopSpace
      }
      
      UIView.animate(withDuration: 0.3) {[weak self] in
        guard let weakSelf = self else {
          return
        }
        weakSelf.view.layoutSubviews()
        // Вызов updateMediaLibraryControllerUI удален, т.к. функция была удалена
      }
    }
}
