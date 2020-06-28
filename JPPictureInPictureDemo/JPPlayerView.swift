//
//  JPPlayerView.swift
//  JPPictureInPictureDemo
//
//  Created by 周健平 on 2020/6/25.
//

import UIKit
import AVKit

class JPPlayerView: UIView {
    
    override class var layerClass: AnyClass {
        get {
            return AVPlayerLayer.self
        }
    }
    
    var playerLayer : AVPlayerLayer {
        get {
            return layer as! AVPlayerLayer
        }
    }
    
    let urlAsset : AVURLAsset
    let playerItem : AVPlayerItem
    let player : AVPlayer
    var timeObserver : Any?
    
    let controlView : JPPlayerControlView
    
    var pipCtr : AVPictureInPictureController?
    
    fileprivate var _isPlayDone : Bool = false
    
    fileprivate var _timer : Timer?
    
    init(frame: CGRect, assetURL: URL) {
        self.urlAsset = AVURLAsset(url: assetURL)
        self.playerItem = AVPlayerItem(asset: self.urlAsset)
        self.player = AVPlayer(playerItem: self.playerItem)
        self.controlView = JPPlayerControlView(frame: CGRect(origin: .zero, size: frame.size))
        
        super.init(frame: frame)
        __setupUI()
        __setupActionAndObserver()
        __setupPipCtr()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        __removeTimer()
        
        if let pipCtr = pipCtr {
            pipCtr.removeObserver(self, forKeyPath: #keyPath(AVPictureInPictureController.isPictureInPicturePossible))
            pipCtr.removeObserver(self, forKeyPath: #keyPath(AVPictureInPictureController.isPictureInPictureActive))
        }
        
        NotificationCenter.default.removeObserver(self)
        
        player.removeObserver(self, forKeyPath: #keyPath(AVPlayer.rate))
        
        if let timeObserver = timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        
        player.replaceCurrentItem(with: nil)
    }
}

extension JPPlayerView {
    fileprivate func __setupUI() {
        clipsToBounds = true
        backgroundColor = .black
        
        playerLayer.videoGravity = .resizeAspect
        playerLayer.player = player
        
        controlView.layer.zPosition = 99
        addSubview(controlView)
    }
    
    fileprivate func __setupActionAndObserver() {
        controlView.resumeBtn.addTarget(self, action: #selector(__resumeOrPause), for: .touchUpInside)
        controlView.pipBtn?.addTarget(self, action: #selector(__togglePictureInPicture), for: .touchUpInside)
        let tapGR = UITapGestureRecognizer(target: self, action: #selector(__tap))
        tapGR.delegate = self
        controlView.addGestureRecognizer(tapGR)
        
        NotificationCenter.default.addObserver(self, selector: #selector(__playDidEnd), name: NSNotification.Name(rawValue: "AVPlayerItemDidPlayToEndTimeNotification"), object: playerItem)
        
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 1), queue: DispatchQueue.main) { [weak self] (time) in
            guard let currentItem = self?.playerItem else {return}
            let loadedRanges = currentItem.seekableTimeRanges
            if loadedRanges.count > 0 && currentItem.duration.timescale != 0 {
                let progress = CMTimeGetSeconds(time) / CMTimeGetSeconds(currentItem.duration)
                self?.controlView.progress = Float(progress)
            } else {
                self?.controlView.progress = 0
            }
        }
        
        player.addObserver(self, forKeyPath: #keyPath(AVPlayer.rate), options: .new, context: nil)
    }
    
    fileprivate func __setupPipCtr() {
        if AVPictureInPictureController.isPictureInPictureSupported() == true {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback)
                try AVAudioSession.sharedInstance().setActive(true, options: [])
            } catch {
                
            }
            
            pipCtr = AVPictureInPictureController(playerLayer: playerLayer)
            guard let pipCtr = pipCtr else {
                return
            }
            pipCtr.addObserver(self, forKeyPath: #keyPath(AVPictureInPictureController.isPictureInPicturePossible), options: .new, context: nil)
            pipCtr.addObserver(self, forKeyPath: #keyPath(AVPictureInPictureController.isPictureInPictureActive), options: .new, context: nil)
        }
    }
}


extension JPPlayerView {
    @objc fileprivate func __resumeOrPause() {
        __removeTimer()
        controlView.isShowResumeBtn = true
        
        controlView.resumeBtn.isSelected = !controlView.resumeBtn.isSelected
        if controlView.resumeBtn.isSelected == true {
            if _isPlayDone == true {
                _isPlayDone = false
                player.seek(to: .zero)
            }
            player.play()
            __addTimer()
        } else {
            player.pause()
        }
    }
    
    @objc fileprivate func __togglePictureInPicture() {
        __addTimer()
        
        guard let pipCtr = pipCtr else {
            return
        }
        if pipCtr.isPictureInPictureActive {
            controlView.pipBtn?.isSelected = false
            pipCtr.stopPictureInPicture()
        } else {
            controlView.pipBtn?.isSelected = true
            pipCtr.startPictureInPicture()
        }
    }
}

extension JPPlayerView {
    @objc fileprivate func __playDidEnd() {
        _isPlayDone = true
        controlView.resumeBtn.isSelected = false
        
        __removeTimer()
        controlView.isShowResumeBtn = true
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        
        let isSelected  = player.rate > 0
        if controlView.resumeBtn.isSelected != isSelected {
            __resumeOrPause()
        }
        
        guard let pipCtr = pipCtr, let pipBtn = controlView.pipBtn else {
            return
        }
        pipBtn.isEnabled = pipCtr.isPictureInPicturePossible
        pipBtn.isSelected = pipCtr.isPictureInPictureActive
    }
    
    @objc fileprivate func __tap() {
        controlView.isShowResumeBtn = !controlView.isShowResumeBtn
        if controlView.isShowResumeBtn == true {
            __addTimer()
        }
    }
}

extension JPPlayerView : UIGestureRecognizerDelegate {
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if controlView.isShowResumeBtn == true {
            let location = gestureRecognizer.location(in: controlView)
            if controlView.blurView.frame.contains(location) {
                return false
            }
        }
        return true
    }
}

extension JPPlayerView {
    fileprivate func __addTimer() {
        __removeTimer()
        _timer = Timer.init(timeInterval: 5.0, repeats: false, block: { [weak self] (timer) in
            self?.controlView.isShowResumeBtn = false
        })
        guard let timer = _timer else {return}
        RunLoop.main.add(timer, forMode: .common)
    }
    
    fileprivate func __removeTimer() {
        if let timer = _timer {
            timer.invalidate()
            _timer = nil
        }
    }
}
