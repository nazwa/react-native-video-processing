//
//  RNVideoTrimmer.swift
//  RNVideoProcessing
//

import Foundation
import AVFoundation

enum QUALITY_ENUM: String {
  case QUALITY_LOW = "low"
  case QUALITY_MEDIUM = "medium"
  case QUALITY_HIGHEST = "highest"
  case QUALITY_640x480 = "640x480"
  case QUALITY_960x540 = "960x540"
  case QUALITY_1280x720 = "1280x720"
  case QUALITY_1920x1080 = "1920x1080"
  case QUALITY_3840x2160 = "3840x2160"
  case QUALITY_PASS_THROUGH = "passthrough"
}

@objc(RNVideoTrimmer)
class RNVideoTrimmer: NSObject {
  
  @objc func getVideoOrientationFromAsset(asset : AVAsset) -> UIImageOrientation {
    let videoTrack: AVAssetTrack? = asset.tracks(withMediaType: AVMediaTypeVideo)[0]
    let size = videoTrack!.naturalSize
    
    let txf: CGAffineTransform = videoTrack!.preferredTransform
    
    if (size.width == txf.tx && size.height == txf.ty) {
      return UIImageOrientation.left;
    } else if (txf.tx == 0 && txf.ty == 0) {
      return UIImageOrientation.right;
    } else if (txf.tx == 0 && txf.ty == size.width) {
      return UIImageOrientation.down;
    } else {
      return UIImageOrientation.up;
    }
  }
  
  @objc func addWatermark(_ source: String, callback: @escaping RCTResponseSenderBlock) {
    let sourceURL = getSourceURL(source: source)
    let asset = AVAsset(url: sourceURL as URL)
    
    // Video Composition
    let videoComposition = AVMutableVideoComposition(propertiesOf: asset)
    let clipVideoTrack: AVAssetTrack! = asset.tracks(withMediaType: AVMediaTypeVideo)[0]
    let videoSize = clipVideoTrack.naturalSize
    
    //adding the image layer
    // Watermark!
    // https://stackoverflow.com/questions/7205820/iphone-watermark-on-recorded-video?noredirect=1&lq=1
    //    let imglogo = UIImage(named: "splashIcon.png")
    let imglogo = UIImage(named: "watermark.png")
    let watermarkLayer = CALayer()
    watermarkLayer.contents = imglogo?.cgImage
    watermarkLayer.frame = CGRect(x: videoSize.width - 150 - 25, y: 25 ,width: 150, height: 22)
    watermarkLayer.opacity = 1
    
    let parentlayer = CALayer()
    let videoLayer = CALayer()
    
    parentlayer.frame = CGRect(x: 0, y: 0, width: videoSize.width, height: videoSize.height)
    videoLayer.frame = CGRect(x: 0, y: 0, width: videoSize.width, height: videoSize.height)
    
    parentlayer.addSublayer(videoLayer)
    parentlayer.addSublayer(watermarkLayer)
    
    videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayers: [videoLayer], in: parentlayer)
    
    let instruction : AVMutableVideoCompositionInstruction = AVMutableVideoCompositionInstruction()
    instruction.timeRange = CMTimeRange(start: kCMTimeZero, end: asset.duration)
    
    let transformer = AVMutableVideoCompositionLayerInstruction(assetTrack: clipVideoTrack)
    
    instruction.layerInstructions = [transformer]
    videoComposition.instructions = [instruction]
    
    // Output files
    let manager = FileManager.default
    guard let documentDirectory = try? manager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      else {
        callback(["Error creating FileManager", NSNull()])
        return
    }
    
    var outputURL = documentDirectory.appendingPathComponent("output")
    do {
      try manager.createDirectory(at: outputURL, withIntermediateDirectories: true, attributes: nil)
      let name = randomString()
      outputURL = outputURL.appendingPathComponent("\(name).mp4")
    } catch {
      callback([error.localizedDescription, NSNull()])
      print(error)
    }
    
    guard
      let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720)
      else {
        callback(["Error creating AVAssetExportSession", NSNull()])
        return
    }
    
    exportSession.timeRange = CMTimeRange(start: kCMTimeZero, end: asset.duration)
    exportSession.outputURL = outputURL
    exportSession.outputFileType = AVFileTypeMPEG4
    exportSession.shouldOptimizeForNetworkUse = true
    exportSession.videoComposition = videoComposition
    
    exportSession.exportAsynchronously {
      
      switch exportSession.status {
      case .completed:
        print("SUCCESS");
        callback( [NSNull(), outputURL.absoluteString] )
        
      case .failed:
        print("Failed");
        callback( ["Failed: \(exportSession.error)", NSNull()] )
        
      case .cancelled:
        print("Cancelled");
        callback( ["Cancelled: \(exportSession.error)", NSNull()] )
        
      default: break
      }
    }
  }
  
  @objc func crop(_ source: String, options: NSDictionary, callback: @escaping RCTResponseSenderBlock) {
    var cropAspect:Float? = 760/1280
    var sTime:Float? = 0
    var eTime:Float? = 0.3
    
    if let _aspect = options.object(forKey: "cropAspect") as? NSNumber {
      cropAspect = _aspect.floatValue
    }
    if let num = options.object(forKey: "startTime") as? NSNumber {
      sTime = num.floatValue
    }
    if let num = options.object(forKey: "endTime") as? NSNumber {
      eTime = num.floatValue
    }
    
    let sourceURL = getSourceURL(source: source)
    let asset = AVAsset(url: sourceURL as URL)
    
    // Time range
    let startTime = CMTime(seconds: Double(sTime!), preferredTimescale: 1000)
    let endTime = CMTime(seconds: Double(eTime!), preferredTimescale: 1000)
    let timeRange = CMTimeRange(start: startTime, end: endTime)
    
    // Video Composition
    let videoComposition = AVMutableVideoComposition(propertiesOf: asset)
    let clipVideoTrack: AVAssetTrack! = asset.tracks(withMediaType: AVMediaTypeVideo)[0]
    let videoOrientation = self.getVideoOrientationFromAsset(asset: asset)
    
    var cropOffsetX : CGFloat = 0;
    var cropOffsetY : CGFloat = 0;
    var cropWidth : CGFloat = 0;
    var cropHeight : CGFloat = 0;
    
    let videoWidth : CGFloat
    let videoHeight : CGFloat
    
    if ( videoOrientation == UIImageOrientation.up || videoOrientation == UIImageOrientation.down ) {
      videoWidth = clipVideoTrack.naturalSize.height
      videoHeight = clipVideoTrack.naturalSize.width
    } else {
      videoWidth = clipVideoTrack.naturalSize.width
      videoHeight = clipVideoTrack.naturalSize.height
    }
    
    if (videoWidth > videoHeight) {
      cropWidth = videoHeight * CGFloat(cropAspect!)
      cropHeight = videoHeight
      cropOffsetX = (videoWidth - cropWidth) / 2
      cropOffsetY = 0
    } else {
      cropWidth = videoWidth
      cropHeight = videoWidth / CGFloat(cropAspect!)
      cropOffsetX = 0
      cropOffsetY = (videoHeight - cropHeight) / 2
    }
    
    videoComposition.frameDuration = CMTimeMake(1, 30)
    videoComposition.renderSize = CGSize(width: cropWidth, height: cropHeight)
    videoComposition.renderScale = 1.0
    
    var t1 = CGAffineTransform.identity
    var t2 = CGAffineTransform.identity
    
    let transformer = AVMutableVideoCompositionLayerInstruction(assetTrack: clipVideoTrack)
    
    
    switch videoOrientation {
    case UIImageOrientation.up:
      t1 = CGAffineTransform(translationX: clipVideoTrack.naturalSize.height - cropOffsetX, y: 0 - cropOffsetY );
      t2 = t1.rotated(by: CGFloat(Double.pi / 2) );
      break;
    case UIImageOrientation.left:
      t1 = CGAffineTransform(translationX: clipVideoTrack.naturalSize.width - cropOffsetX, y: clipVideoTrack.naturalSize.height - cropOffsetY );
      t2 = t1.rotated(by: CGFloat(Double.pi)  );
      break;
    case UIImageOrientation.right:
      t1 = CGAffineTransform(translationX: 0 - cropOffsetX, y: 0 - cropOffsetY );
      t2 = t1.rotated(by: 0);
      break;
    case UIImageOrientation.down:
      t1 = CGAffineTransform(translationX: 0 - cropOffsetX, y: clipVideoTrack.naturalSize.width - cropOffsetY ); // not fixed width is the real height in upside down
      t2 = t1.rotated(by: -(CGFloat)(Double.pi / 2) );
      break;
    default:
      NSLog("no supported orientation has been found in this video");
      break;
    }
    
    let finalTransform: CGAffineTransform = t2
    transformer.setTransform(finalTransform, at: kCMTimeZero)
    
    // Output files
    let manager = FileManager.default
    guard let documentDirectory = try? manager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      else {
        callback(["Error creating FileManager", NSNull()])
        return
    }
    
    var outputURL = documentDirectory.appendingPathComponent("output")
    do {
      try manager.createDirectory(at: outputURL, withIntermediateDirectories: true, attributes: nil)
      let name = randomString()
      outputURL = outputURL.appendingPathComponent("\(name).mp4")
    } catch {
      callback([error.localizedDescription, NSNull()])
      print(error)
    }
    
    guard
      let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720)
      else {
        callback(["Error creating AVAssetExportSession", NSNull()])
        return
    }
    
    exportSession.timeRange = timeRange
    exportSession.outputURL = outputURL
    exportSession.outputFileType = AVFileTypeMPEG4
    exportSession.shouldOptimizeForNetworkUse = true
    exportSession.videoComposition = videoComposition
    
    exportSession.exportAsynchronously {
      
      switch exportSession.status {
      case .completed:
        print("SUCCESS");
        callback( [NSNull(), outputURL.absoluteString] )
        
      case .failed:
        print("Failed");
        callback( ["Failed: \(exportSession.error)", NSNull()] )
        
      case .cancelled:
        print("Cancelled");
        callback( ["Cancelled: \(exportSession.error)", NSNull()] )
        
      default: break
      }
    }
  }
  
  @objc func trim(_ source: String, options: NSDictionary, callback: @escaping RCTResponseSenderBlock) {
    
    var sTime:Float?
    var eTime:Float?
    if let num = options.object(forKey: "startTime") as? NSNumber {
      sTime = num.floatValue
    }
    if let num = options.object(forKey: "endTime") as? NSNumber {
      eTime = num.floatValue
    }
    
    let quality = ((options.object(forKey: "quality") as? String) != nil) ? options.object(forKey: "quality") as! String : ""
    let saveToCameraRoll = options.object(forKey: "saveToCameraRoll") as? Bool ?? false
    let saveWithCurrentDate = options.object(forKey: "saveWithCurrentDate") as? Bool ?? false
    
    let manager = FileManager.default
    guard let documentDirectory = try? manager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      else {
        callback(["Error creating FileManager", NSNull()])
        return
    }
    
    let sourceURL = getSourceURL(source: source)
    let asset = AVAsset(url: sourceURL as URL)
    if eTime == nil {
      eTime = Float(asset.duration.seconds)
    }
    if sTime == nil {
      sTime = 0
    }
    var outputURL = documentDirectory.appendingPathComponent("output")
    do {
      try manager.createDirectory(at: outputURL, withIntermediateDirectories: true, attributes: nil)
      let name = randomString()
      outputURL = outputURL.appendingPathComponent("\(name).mp4")
    } catch {
      callback([error.localizedDescription, NSNull()])
      print(error)
    }
    
    //Remove existing file
    _ = try? manager.removeItem(at: outputURL)
    
    let useQuality = getQualityForAsset(quality: quality, asset: asset)
    
    print("RNVideoTrimmer passed quality: \(quality). useQuality: \(useQuality)")
    
    guard let exportSession = AVAssetExportSession(asset: asset, presetName: useQuality)
      else {
        callback(["Error creating AVAssetExportSession", NSNull()])
        return
    }
    exportSession.outputURL = NSURL.fileURL(withPath: outputURL.path)
    exportSession.outputFileType = AVFileTypeMPEG4
    exportSession.shouldOptimizeForNetworkUse = true
    
    if saveToCameraRoll && saveWithCurrentDate {
      let metaItem = AVMutableMetadataItem()
      metaItem.key = AVMetadataCommonKeyCreationDate as (NSCopying & NSObjectProtocol)?
      metaItem.keySpace = AVMetadataKeySpaceCommon
      metaItem.value = NSDate() as (NSCopying & NSObjectProtocol)?
      exportSession.metadata = [metaItem]
    }
    
    let startTime = CMTime(seconds: Double(sTime!), preferredTimescale: 1000)
    let endTime = CMTime(seconds: Double(eTime!), preferredTimescale: 1000)
    let timeRange = CMTimeRange(start: startTime, end: endTime)
    
    exportSession.timeRange = timeRange
    exportSession.exportAsynchronously{
      switch exportSession.status {
      case .completed:
        callback( [NSNull(), outputURL.absoluteString] )
        if saveToCameraRoll {
          UISaveVideoAtPathToSavedPhotosAlbum(outputURL.relativePath, self, nil, nil)
        }
        
      case .failed:
        callback( ["Failed: \(exportSession.error)", NSNull()] )
        
      case .cancelled:
        callback( ["Cancelled: \(exportSession.error)", NSNull()] )
        
      default: break
      }
    }
  }
  
  @objc func boomerang(_ source: String, options: NSDictionary, callback: @escaping RCTResponseSenderBlock) {
    
    let quality = ""
    
    let manager = FileManager.default
    guard let documentDirectory = try? manager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      else {
        callback(["Error creating FileManager", NSNull()])
        return
    }
    
    let sourceURL = getSourceURL(source: source)
    let firstAsset = AVAsset(url: sourceURL as URL)
    
    let mixComposition = AVMutableComposition()
    let track = mixComposition.addMutableTrack(withMediaType: AVMediaTypeVideo, preferredTrackID: Int32(kCMPersistentTrackID_Invalid))
    
    
    var outputURL = documentDirectory.appendingPathComponent("output")
    var finalURL = documentDirectory.appendingPathComponent("output")
    do {
      try manager.createDirectory(at: outputURL, withIntermediateDirectories: true, attributes: nil)
      try manager.createDirectory(at: finalURL, withIntermediateDirectories: true, attributes: nil)
      let name = randomString()
      outputURL = outputURL.appendingPathComponent("\(name).mp4")
      finalURL = finalURL.appendingPathComponent("\(name)merged.mp4")
    } catch {
      callback([error.localizedDescription, NSNull()])
      print(error)
    }
    
    //Remove existing file
    _ = try? manager.removeItem(at: outputURL)
    _ = try? manager.removeItem(at: finalURL)
    
    let useQuality = getQualityForAsset(quality: quality, asset: firstAsset)
    
    //    print("RNVideoTrimmer passed quality: \(quality). useQuality: \(useQuality)")
    
    AVUtilities.reverse(firstAsset, outputURL: outputURL, completion: { [unowned self] (reversedAsset: AVAsset) in
      
      
      let secondAsset = reversedAsset
      
      // Credit: https://www.raywenderlich.com/94404/play-record-merge-videos-ios-swift
      do {
        try track.insertTimeRange(CMTimeRangeMake(kCMTimeZero, firstAsset.duration), of: firstAsset.tracks(withMediaType: AVMediaTypeVideo)[0], at: kCMTimeZero)
      } catch _ {
        callback( ["Failed: Could not load 1st track", NSNull()] )
        return
      }
      
      do {
        try track.insertTimeRange(CMTimeRangeMake(kCMTimeZero, secondAsset.duration), of: secondAsset.tracks(withMediaType: AVMediaTypeVideo)[0], at: mixComposition.duration)
      } catch _ {
        callback( ["Failed: Could not load 2nd track", NSNull()] )
        return
      }
      
      
      guard let exportSession = AVAssetExportSession(asset: mixComposition, presetName: useQuality) else {
        callback(["Error creating AVAssetExportSession", NSNull()])
        return
      }
      exportSession.outputURL = NSURL.fileURL(withPath: finalURL.path)
      exportSession.outputFileType = AVFileTypeMPEG4
      exportSession.shouldOptimizeForNetworkUse = true
      let startTime = CMTime(seconds: Double(0), preferredTimescale: 1000)
      let endTime = CMTime(seconds: mixComposition.duration.seconds, preferredTimescale: 1000)
      let timeRange = CMTimeRange(start: startTime, end: endTime)
      
      exportSession.timeRange = timeRange
      
      exportSession.exportAsynchronously{
        switch exportSession.status {
        case .completed:
          callback( [NSNull(), finalURL.absoluteString] )
          
        case .failed:
          callback( ["Failed: \(exportSession.error)", NSNull()] )
          
        case .cancelled:
          callback( ["Cancelled: \(exportSession.error)", NSNull()] )
          
        default: break
        }
      }
    })
  }
  
  @objc func reverse(_ source: String, options: NSDictionary, callback: @escaping RCTResponseSenderBlock) {
    
    let quality = ""
    
    let manager = FileManager.default
    guard let documentDirectory = try? manager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      else {
        callback(["Error creating FileManager", NSNull()])
        return
    }
    
    let sourceURL = getSourceURL(source: source)
    let asset = AVAsset(url: sourceURL as URL)
    
    var outputURL = documentDirectory.appendingPathComponent("output")
    do {
      try manager.createDirectory(at: outputURL, withIntermediateDirectories: true, attributes: nil)
      let name = randomString()
      outputURL = outputURL.appendingPathComponent("\(name).mp4")
    } catch {
      callback([error.localizedDescription, NSNull()])
      print(error)
    }
    
    //Remove existing file
    _ = try? manager.removeItem(at: outputURL)
    
    let useQuality = getQualityForAsset(quality: quality, asset: asset)
    
    print("RNVideoTrimmer passed quality: \(quality). useQuality: \(useQuality)")
    
    AVUtilities.reverse(asset, outputURL: outputURL, completion: { [unowned self] (asset: AVAsset) in
      callback( [NSNull(), outputURL.absoluteString] )
    })
  }
  
  @objc func compress(_ source: String, options: NSDictionary, callback: @escaping RCTResponseSenderBlock) {
    
    var width = options.object(forKey: "width") as? Float
    var height = options.object(forKey: "height") as? Float
    let bitrateMultiplier = options.object(forKey: "bitrateMultiplier") as? Float ?? 1
    let saveToCameraRoll = options.object(forKey: "saveToCameraRoll") as? Bool ?? false
    let minimumBitrate = options.object(forKey: "minimumBitrate") as? Float
    let saveWithCurrentDate = options.object(forKey: "saveWithCurrentDate") as? Bool ?? false
    let removeAudio = options.object(forKey: "removeAudio") as? Bool ?? false
    
    let manager = FileManager.default
    guard let documentDirectory = try? manager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      else {
        callback(["Error creating FileManager", NSNull()])
        return
    }
    
    let sourceURL = getSourceURL(source: source)
    let asset = AVAsset(url: sourceURL as URL)
    
    guard let videoTrack = asset.tracks(withMediaType: AVMediaTypeVideo).first else  {
      callback(["Error getting track info", NSNull()])
      return
    }
    
    let naturalSize = videoTrack.naturalSize.applying(videoTrack.preferredTransform)
    let bps = videoTrack.estimatedDataRate
    width = width ?? Float(abs(naturalSize.width))
    height = height ?? Float(abs(naturalSize.height))
    var averageBitrate = bps / bitrateMultiplier
    if minimumBitrate != nil {
      if averageBitrate < minimumBitrate! {
        averageBitrate = minimumBitrate!
      }
      if bps < minimumBitrate! {
        averageBitrate = bps
      }
    }
    
    var outputURL = documentDirectory.appendingPathComponent("output")
    do {
      try manager.createDirectory(at: outputURL, withIntermediateDirectories: true, attributes: nil)
      let name = randomString()
      outputURL = outputURL.appendingPathComponent("\(name)-compressed.mp4")
    } catch {
      callback([error.localizedDescription, NSNull()])
      print(error)
    }
    
    //Remove existing file
    _ = try? manager.removeItem(at: outputURL)
    
    let compressionEncoder = SDAVAssetExportSession(asset: asset)
    if compressionEncoder == nil {
      callback(["Error creating AVAssetExportSession", NSNull()])
      return
    }
    compressionEncoder!.outputFileType = AVFileTypeMPEG4
    compressionEncoder!.outputURL = NSURL.fileURL(withPath: outputURL.path)
    compressionEncoder!.shouldOptimizeForNetworkUse = true
    if saveToCameraRoll && saveWithCurrentDate {
      let metaItem = AVMutableMetadataItem()
      metaItem.key = AVMetadataCommonKeyCreationDate as (NSCopying & NSObjectProtocol)?
      metaItem.keySpace = AVMetadataKeySpaceCommon
      metaItem.value = NSDate() as (NSCopying & NSObjectProtocol)?
      compressionEncoder!.metadata = [metaItem]
    }
    compressionEncoder?.videoSettings = [
      AVVideoCodecKey: AVVideoCodecH264,
      AVVideoWidthKey: NSNumber.init(value: width!),
      AVVideoHeightKey: NSNumber.init(value: height!),
      AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: NSNumber.init(value: averageBitrate),
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
      ]
    ]
    if !removeAudio {
      compressionEncoder?.audioSettings = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVNumberOfChannelsKey: 1,
        AVSampleRateKey: 44100,
        AVEncoderBitRateKey: 128000
      ]
    }
    compressionEncoder!.exportAsynchronously(completionHandler: {
      switch compressionEncoder!.status {
      case .completed:
        callback( [NSNull(), outputURL.absoluteString] )
        if saveToCameraRoll {
          UISaveVideoAtPathToSavedPhotosAlbum(outputURL.relativePath, self, nil, nil)
        }
      case .failed:
        callback( ["Failed: \(compressionEncoder!.error)", NSNull()] )
        
      case .cancelled:
        callback( ["Cancelled: \(compressionEncoder!.error)", NSNull()] )
        
      default: break
      }
    })
  }
  
  @objc func getAssetInfo(_ source: String, callback: RCTResponseSenderBlock) {
    let sourceURL = getSourceURL(source: source)
    let asset = AVAsset(url: sourceURL)
    var assetInfo: [String: Any] = [
      "duration" : asset.duration.seconds
    ]
    if let track = asset.tracks(withMediaType: AVMediaTypeVideo).first {
      let naturalSize = track.naturalSize
      let t = track.preferredTransform
      let isPortrait = t.a == 0 && abs(t.b) == 1 && t.d == 0
      let size = [
        "width": isPortrait ? naturalSize.height : naturalSize.width,
        "height": isPortrait ? naturalSize.width : naturalSize.height
      ]
      assetInfo["size"] = size
      assetInfo["frameRate"] = Int(round(track.nominalFrameRate))
      assetInfo["bitrate"] = Int(round(track.estimatedDataRate))
    }
    callback( [NSNull(), assetInfo] )
  }
  
  @objc func getPreviewImageAtPosition(_ source: String, atTime: Float = 0, maximumSize: NSDictionary, format: String = "base64", callback: @escaping RCTResponseSenderBlock) {
    let sourceURL = getSourceURL(source: source)
    let asset = AVAsset(url: sourceURL)
    
    var width: CGFloat = 1080
    if let _width = maximumSize.object(forKey: "width") as? CGFloat {
      width = _width
    }
    var height: CGFloat = 1080
    if let _height = maximumSize.object(forKey: "height") as? CGFloat {
      height = _height
    }
    
    let imageGenerator = AVAssetImageGenerator(asset: asset)
    imageGenerator.maximumSize = CGSize(width: width, height: height)
    imageGenerator.appliesPreferredTrackTransform = true
    var second = atTime
    if atTime > Float(asset.duration.seconds) || atTime < 0 {
      second = 0
    }
    let timestamp = CMTime(seconds: Double(second), preferredTimescale: 600)
    do {
      let imageRef = try imageGenerator.copyCGImage(at: timestamp, actualTime: nil)
      let image = UIImage(cgImage: imageRef)
      if ( format == "base64" ) {
        let imgData = UIImagePNGRepresentation(image)
        let base64string = imgData?.base64EncodedString(options: Data.Base64EncodingOptions.init(rawValue: 0))
        if base64string != nil {
          callback( [NSNull(), base64string!] )
        } else {
          callback( ["Unable to convert to base64)", NSNull()]  )
        }
      } else if ( format == "JPEG" ) {
        let imgData = UIImageJPEGRepresentation(image, 1.0)
        
        let fileName = ProcessInfo.processInfo.globallyUniqueString
        let fullPath = "\(NSTemporaryDirectory())\(fileName).jpg"
        
        try imgData?.write(to: URL(fileURLWithPath: fullPath), options: .atomic)
        
        let imageWidth = imageRef.width
        let imageHeight = imageRef.height
        let imageFormattedData: [AnyHashable: Any] = ["uri": fullPath, "width": imageWidth, "height": imageHeight]
        
        callback( [NSNull(), imageFormattedData] )
      } else {
        callback( ["Failed format. Expected one of 'base64' or 'JPEG'", NSNull()] )
      }
    } catch {
      callback( ["Failed to convert base64: \(error.localizedDescription)", NSNull()] )
    }
  }
  
  func randomString() -> String {
    let letters: NSString = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    let randomString: NSMutableString = NSMutableString(capacity: 20)
    let s:String = "RNTrimmer-Temp-Video"
    for _ in 0...19 {
      randomString.appendFormat("%C", letters.character(at: Int(arc4random_uniform(UInt32(letters.length)))))
    }
    return s.appending(randomString as String)
  }
  
  func getSourceURL(source: String) -> URL {
    var sourceURL: URL
    if source.contains("assets-library") {
      sourceURL = NSURL(string: source) as! URL
    } else {
      let bundleUrl = Bundle.main.resourceURL!
      sourceURL = URL(string: source, relativeTo: bundleUrl)!
    }
    return sourceURL
  }
  
  func getQualityForAsset(quality: String, asset: AVAsset) -> String {
    var useQuality: String
    
    switch quality {
    case QUALITY_ENUM.QUALITY_LOW.rawValue:
      useQuality = AVAssetExportPresetLowQuality
      
    case QUALITY_ENUM.QUALITY_MEDIUM.rawValue:
      useQuality = AVAssetExportPresetMediumQuality
      
    case QUALITY_ENUM.QUALITY_HIGHEST.rawValue:
      useQuality = AVAssetExportPresetHighestQuality
      
    case QUALITY_ENUM.QUALITY_640x480.rawValue:
      useQuality = AVAssetExportPreset640x480
      
    case QUALITY_ENUM.QUALITY_960x540.rawValue:
      useQuality = AVAssetExportPreset960x540
      
    case QUALITY_ENUM.QUALITY_1280x720.rawValue:
      useQuality = AVAssetExportPreset1280x720
      
    case QUALITY_ENUM.QUALITY_1920x1080.rawValue:
      useQuality = AVAssetExportPreset1920x1080
      
    case QUALITY_ENUM.QUALITY_3840x2160.rawValue:
      if #available(iOS 9.0, *) {
        useQuality = AVAssetExportPreset3840x2160
      } else {
        useQuality = AVAssetExportPresetPassthrough
      }
      
    default:
      useQuality = AVAssetExportPresetPassthrough
    }
    
    let compatiblePresets = AVAssetExportSession.exportPresets(compatibleWith: asset)
    if !compatiblePresets.contains(useQuality) {
      useQuality = AVAssetExportPresetPassthrough
    }
    return useQuality
  }
}
