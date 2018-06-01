//
//  ViewController.h
//  CameraLiveStream
//
//  Created by Anirban on 8/23/17.
//  Copyright © 2017 Anirban. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <VideoToolbox/VideoToolbox.h>
#import "GCDAsyncUdpSocket.h"
#import "H264HwEncoderImpl.h"
@interface ViewController : UIViewController<AVCaptureVideoDataOutputSampleBufferDelegate,GCDAsyncUdpSocketDelegate,H264HwEncoderImplDelegate>

@property (nonatomic, assign) CMVideoFormatDescriptionRef formatDesc;
@property (nonatomic, assign) VTDecompressionSessionRef decompressionSession;
@property (nonatomic, assign) int spsSize;
//@property (weak, nonatomic) IBOutlet UIView *videoContainerView;
//@property (strong, nonatomic) IBOutlet UIView *videoPreview;
//@property (strong, nonatomic) IBOutlet UIImageView *videoPreview;
@property (strong, nonatomic) IBOutlet UIImageView *previewVideo;
@property (nonatomic, assign) int ppsSize;
//@property (strong, nonatomic) IBOutlet UIView *videoPreview;
@end

