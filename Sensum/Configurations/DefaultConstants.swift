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

import Foundation
import UIKit
import MediaPipeTasksVision

// MARK: Define default constants
struct DefaultConstants {

  static let lineWidth: CGFloat = 2
  static let pointRadius: CGFloat = 2
  static let pointColor = UIColor.yellow
  static let pointFillColor = UIColor.red

  static let lineColor = UIColor(red: 0, green: 127/255.0, blue: 139/255.0, alpha: 1)

  static var numPoses: Int = 1
  static var minPoseDetectionConfidence: Float = 0.5
  static var minPosePresenceConfidence: Float = 0.5
  static var minTrackingConfidence: Float = 0.5
  static let model: Model = .pose_landmarker_full
  static let delegate: PoseLandmarkerDelegate = .GPU
}

// MARK: Model
enum Model: Int {
  case pose_landmarker_full

  var name: String {
    return "Pose landmarker (Full)"
  }

  var modelPath: String? {
    return Bundle.main.path(forResource: "pose_landmarker_full", ofType: "task")
  }

  // Сохраняем init для совместимости, хотя он будет использоваться редко
  init?(name: String) {
    if name == "Pose landmarker (Full)" {
      self = .pose_landmarker_full
    } else {
      return nil
    }
  }
}

// MARK: PoseLandmarkerDelegate
enum PoseLandmarkerDelegate: CaseIterable {
  case GPU
  case CPU

  var name: String {
    switch self {
    case .GPU:
      return "GPU"
    case .CPU:
      return "CPU"
    }
  }

  var delegate: Delegate {
    switch self {
    case .GPU:
      return .GPU
    case .CPU:
      return .CPU
    }
  }

  init?(name: String) {
    switch name {
    case PoseLandmarkerDelegate.GPU.name:
      self = PoseLandmarkerDelegate.GPU
    case PoseLandmarkerDelegate.CPU.name:
      self = PoseLandmarkerDelegate.CPU
    default:
      return nil
    }
  }
}
