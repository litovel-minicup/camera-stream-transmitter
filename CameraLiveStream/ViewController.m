//
//  ViewController.m
//  CameraLiveStream
//
//  Created by Anirban on 8/23/17.
//  Copyright © 2017 Anirban. All rights reserved.
//

#import "ViewController.h"
#import <ReplayKit/ReplayKit.h>
#import "XCDYouTubeVideoPlayerViewController.h"
//@synthesize videoPreview;

@interface ViewController ()
{
    AVCaptureDeviceInput *cameraDeviceInput;
    AVCaptureSession* captureSession;
    H264HwEncoderImpl *h264Encoder;
    dispatch_queue_t backgroundQueue,sendScreenFramesForUploadQueue;
    NSInteger SCREENWIDTH,SCREENHEIGHT;
    CFMutableArrayRef frames;
    
    //IBOutlet UIView *videoPreview;
    int FR;
}
@end

@implementation ViewController

GCDAsyncUdpSocket *udpSocket;
int tag,count;
bool timebaseSet=false;
bool encodeVideo=true;




- (void)viewDidLoad {
    [super viewDidLoad];
    [UIApplication sharedApplication].idleTimerDisabled = YES;

    // Do any additional setup after loading the view, typically from a nib.
    frames=CFArrayCreateMutable(kCFAllocatorDefault, 0, NULL);
    SCREENWIDTH=[UIScreen mainScreen].bounds.size.width;
    SCREENHEIGHT=[UIScreen mainScreen].bounds.size.height;
    tag=0;
    count=0;
    FR=0;
    dispatch_queue_t queue = dispatch_queue_create("com.socketDelegate.queue", DISPATCH_QUEUE_SERIAL);
    backgroundQueue=dispatch_queue_create("com.livestream.backgroundQueue", DISPATCH_QUEUE_SERIAL);
    sendScreenFramesForUploadQueue=dispatch_queue_create("com.sendScreenFramesForUpload.Queue", DISPATCH_QUEUE_SERIAL);
    udpSocket = [[GCDAsyncUdpSocket alloc] initWithDelegate:self delegateQueue:queue];
    NSError *error;
    h264Encoder = [H264HwEncoderImpl alloc];
    [h264Encoder initWithConfiguration];
    [self initializeVideoCaptureSession];
    [h264Encoder initEncode:1280 height:720];
    h264Encoder.delegate = self;
    
    [self startCaputureSession];
    
}


-(void)printFrameRate
{
    //NSLog(@"%d",FR);
    if(CFArrayGetCount(frames)>0)
    {
        CMSampleBufferRef sampleBuffer=(CMSampleBufferRef)CFArrayGetValueAtIndex(frames, 0);
        CFArrayRemoveValueAtIndex(frames, 0);
        [h264Encoder encode:sampleBuffer];
    }
}

-(void) initializeVideoCaptureSession
{
    
    // Create our capture session...
    captureSession = [AVCaptureSession new];
    
    // Get our camera device...
    //AVCaptureDevice *cameraDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    AVCaptureDevice *cameraDevice = [self frontFacingCameraIfAvailable];
    //captureSession.sessionPreset = AVCaptureSessionP
    captureSession.sessionPreset = AVCaptureSessionPreset1280x720;
    
    if ( [cameraDevice lockForConfiguration:NULL] == YES ) {
        cameraDevice.focusMode = AVCaptureFocusModeContinuousAutoFocus;
        cameraDevice.autoFocusRangeRestriction = AVCaptureAutoFocusRangeRestrictionFar;
        [cameraDevice unlockForConfiguration];
    }

    NSError *error;
    
    // Initialize our camera device input...
    cameraDeviceInput = [[AVCaptureDeviceInput alloc] initWithDevice:cameraDevice error:&error];
    
    // Finally, add our camera device input to our capture session.
    if ([captureSession canAddInput:cameraDeviceInput])
    {
        [captureSession addInput:cameraDeviceInput];
    }
    
    // Initialize image output
    AVCaptureVideoDataOutput *output = [AVCaptureVideoDataOutput new];

    [output setAlwaysDiscardsLateVideoFrames:YES];
    
    dispatch_queue_t videoDataOutputQueue = dispatch_queue_create("video_data_output_queue", DISPATCH_QUEUE_SERIAL);
    
    [output setSampleBufferDelegate:self queue:videoDataOutputQueue];
    [output setVideoSettings:[NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:kCVPixelFormatType_32BGRA],(id)kCVPixelBufferPixelFormatTypeKey,nil]];
    
    
    if( [captureSession canAddOutput:output])
    {
        [captureSession addOutput:output];
    }
    
    //AVCaptureVideoPreviewLayer* layer = [AVCaptureVideoPreviewLayer layerWithSession:captureSession];
    
    //layer.frame = VideoView.bounds;
    //[VideoView.layer addSublayer:layer];
    
    
    
    [[output connectionWithMediaType:AVMediaTypeVideo] setEnabled:YES];
    [h264Encoder initEncode:720 height:1280];
    h264Encoder.delegate = self;
}


-(AVCaptureDevice *)frontFacingCameraIfAvailable
{
    NSArray *videoDevices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    AVCaptureDevice *captureDevice = nil;
    for (AVCaptureDevice *device in videoDevices)
    {
        if (device.position == AVCaptureDevicePositionBack)
        {
            captureDevice = device;
            break;
        }
    }
    
    //  couldn't find one on the front, so just get the default video device.
    if (!captureDevice)
    {
        captureDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    
    }
    
    return captureDevice;
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    if ([connection isVideoOrientationSupported]) {
        [connection setVideoOrientation:AVCaptureVideoOrientationLandscapeRight];
    }
    FR++;
    [h264Encoder encode:sampleBuffer];
}


- (void)gotSpsPps:(NSData*)sps pps:(NSData*)pps
{
    //NSLog(@"gotSpsPps %d %d", (int)[sps length], (int)[pps length]);
    
    
    dispatch_async(backgroundQueue, ^{
        [self formAndSendNALUnits:sps];
        [self formAndSendNALUnits:pps];
    });
    
}
- (void)gotEncodedData:(NSData*)data isKeyFrame:(BOOL)isKeyFrame
{
    //NSLog(@"gotEncodedData %d", (int)[data length]);
    //static int framecount = 1;
    
    
    dispatch_async(backgroundQueue, ^{
        [self formAndSendNALUnits:data];
    });
    
}

-(void)formAndSendNALUnits:(NSData*)data
{
    const char startCode[] = "\x00\x00\x00\x01";
    size_t length = (sizeof startCode) - 1;
    int type = [self getNALUType:data];
    NSMutableData *NALUnit=[NSMutableData dataWithBytes:startCode length:length];
    [NALUnit appendData:data];
    
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    
    // getting an NSString
    NSString *host = [prefs stringForKey:@"stream_target_ip"];
    NSInteger port = [prefs integerForKey:@"stream_target_port"];
    
    // NSLog(@"%@", [prefs dictionaryRepresentation]);

    
    [udpSocket sendData:NALUnit toHost:host port:port withTimeout:-1 tag:tag++];
    //NSLog(@"Packet - %d, Size - %lu, Type - %d",count++,[NALUnit length],type);
}


- (int)getNALUType:(NSData *)NALU {
    uint8_t * bytes = (uint8_t *) NALU.bytes;
    
    return bytes[0] & 0x1F;
}

- (void)udpSocket:(GCDAsyncUdpSocket *)sock didSendDataWithTag:(long)tag
{
    //NSLog(@"1");
}

- (void)udpSocket:(GCDAsyncUdpSocket *)sock didNotSendDataWithTag:(long)tag dueToError:(NSError *)error
{
    //NSLog(@"1");
}


-(void) startCaputureSession
{
    // Preview
    AVCaptureVideoPreviewLayer *previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:captureSession];
    previewLayer.frame = self.previewVideo.bounds;
    [previewLayer setBackgroundColor:[[UIColor blackColor] CGColor]];
    [previewLayer setVideoGravity:AVLayerVideoGravityResizeAspectFill];
    [self.previewVideo.layer addSublayer:previewLayer];
    
    [captureSession startRunning];
    NSLog(@"Start Video Capture Session....");
}

-(void) stopCaputureSession
{
    [captureSession stopRunning];
    
    NSLog(@"Stop Video Capture Session....");
}
- (IBAction)startPressed:(id)sender {
        if([captureSession isRunning])
        {
            [self stopCaputureSession];
        }
        else
        {
            [self startCaputureSession];
        }
    
    

}

//-(CVPixelBufferRef)copyPixelBuffer:(CVPixelBufferRef)pixelBuffer
//{
//    if(CFGetTypeID(pixelBuffer) == CVPixelBufferGetTypeID())
//        NSLog(@"%s","copy() cannot be called on a non-CVPixelBuffer");
//    CVPixelBufferRef _copy;
//    CVPixelBufferCreate(nil,
//                        CVPixelBufferGetWidth(pixelBuffer),
//                        CVPixelBufferGetHeight(pixelBuffer),
//                        CVPixelBufferGetPixelFormatType(pixelBuffer),
//                        CVBufferGetAttachments(pixelBuffer, kCVAttachmentMode_ShouldPropagate).take,
//                        &_copy);
//}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
