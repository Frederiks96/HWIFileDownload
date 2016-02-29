# HWIFileDownload

HWIFileDownload simplifies file download with NSURLSession on iOS. It offers a complete set of operations (start, cancel, pause, resume) for parallel download of files with no size limitation. Native reporting of single file download progress and total progress is included.

## Features

Based on `NSURLSession` HWIFileDownload offers system background operation even when the app is not running. Downloads can be started individually, cancelled, paused and resumed. When resuming cancelled downloads, previously downloaded data is reused. Progress is reported with `NSProgress`.

HWIFileDownload is backwards compatible down to iOS 6 (where `NSURLConnection` is used instead of `NSURLSession`).

## Implementation

HWIFileDownload uses a __download identifier__ for starting a download, retrieving progress information, and for handling download completion. The __download identifier__ is a string that must be unique for each individual file download.

To start a download, the app client calls the method `startDownloadWithDownloadIdentifier:fromRemoteURL:` of the `HWIFileDownloader`.

The app client should maintain a custom __download store__ to manage the downloads and the persistent store. The app __download store__ needs to implement the protocol `HWIFileDownloadDelegate` to be called on significant download events.

The delegate is called on download completion. Additional calls are used to control the visibility of the network activity indicator. Optionally the delegate can be called on download progress change for each download item. To control the local name of the downloaded file, the delegate can implement the method `localFileURLForIdentifier:remoteURL:`.

	@protocol HWIFileDownloadDelegate

	- (void)downloadDidCompleteWithIdentifier:(nonnull NSString *)aDownloadIdentifier
                                 localFileURL:(nonnull NSURL *)aLocalFileURL;

	- (void)downloadFailedWithIdentifier:(nonnull NSString *)aDownloadIdentifier
                                   error:(nonnull NSError *)anError
                          httpStatusCode:(NSInteger)aHttpStatusCode
                      errorMessagesStack:(nullable NSArray *)anErrorMessagesStack
                              resumeData:(nullable NSData *)aResumeData;

	- (void)incrementNetworkActivityIndicatorActivityCount;
	- (void)decrementNetworkActivityIndicatorActivityCount;

	@optional

	- (void)downloadProgressChangedForIdentifier:(nonnull NSString *)aDownloadIdentifier;
	- (void)downloadPausedWithIdentifier:(nonnull NSString *)aDownloadIdentifier
                              resumeData:(nullable NSData *)aResumeData;
	- (nullable NSURL *)localFileURLForIdentifier:(nonnull NSString *)aDownloadIdentifier
                                        remoteURL:(nonnull NSURL *)aRemoteURL;
	- (BOOL)downloadAtLocalFileURL:(nonnull NSURL *)aLocalFileURL isValidForDownloadIdentifier:(nonnull NSString *)aDownloadIdentifier;
	- (BOOL)httpStatusCode:(NSInteger)aHttpStatusCode isValidForDownloadIdentifier:(nonnull NSString *)aDownloadIdentifier;
	- (NSTimeInterval)requestTimeoutInterval;
	- (NSTimeInterval)resourceTimeoutInterval;
	- (nullable NSProgress *)rootProgress;

	@end
	
The app needs to hold an instance of the `HWIFileDownloader` that manages the download process. The `HWIDownloader` provides methods for querying and controlling individual download processes.

	- (void)startDownloadWithDownloadIdentifier:(nonnull NSString *)aDownloadIdentifier
                                  fromRemoteURL:(nonnull NSURL *)aRemoteURL;
	- (void)startDownloadWithDownloadIdentifier:(nonnull NSString *)aDownloadIdentifier
                                usingResumeData:(nonnull NSData *)aResumeData;
	- (BOOL)isDownloadingIdentifier:(nonnull NSString *)aDownloadIdentifier;
	- (BOOL)isWaitingForDownloadOfIdentifier:(nonnull NSString *)aDownloadIdentifier;
	- (BOOL)hasActiveDownloads;
	- (void)cancelDownloadWithIdentifier:(nonnull NSString *)aDownloadIdentifier;
	- (void)pauseDownloadWithIdentifier:(nonnull NSString *)aDownloadIdentifier;
	- (nullable HWIFileDownloadProgress *)downloadProgressForIdentifier:(nonnull NSString *)aDownloadIdentifier;
	
	
`HWIFileDownloadProgress` exposes these properties:

	@property (nonatomic, assign, readonly) float downloadProgress;
	@property (nonatomic, assign, readonly) int64_t expectedFileSize;
	@property (nonatomic, assign, readonly) int64_t receivedFileSize;
	@property (nonatomic, assign, readonly) NSTimeInterval estimatedRemainingTime;
	@property (nonatomic, assign, readonly) NSUInteger bytesPerSecondSpeed;
	@property (nonatomic, strong, readwrite, nullable) NSString *lastLocalizedDescription;
	@property (nonatomic, strong, readwrite, nullable) NSString *lastLocalizedAdditionalDescription;
	@property (nonatomic, strong, readonly, nonnull) NSProgress *nativeProgress;
	

## Demo App

The demo app shows a sample setup and integration of HWIFileDownload.

The app __download store__ is implemented with the custom class `DownloadStore`.

The app delegate of the demo app holds an instance of the `DownloadStore` and an instance of the `HWIFileDownloader`.

## Workflows and Scenarios

### Start and Restart

On app start a list of all downloads is collected. All items are downloaded that are not downloaded yet.

### Cancel

On "Cancel" all running downloads are cancelled. On iOS 7 (and later) incompletely downloaded data is passed asynchronously as resume data.

### Crash

On "Crash" the app crashes. On iOS 7 (and later) started downloads continue in the background even though the app is not running anymore. On iOS 6 download does not continue.

### Force Quit

After the app has been killed by the user, downloads do not continue in the background. On iOS 7 (and later) resume data is passed back.

### Refresh

By pulling down the table view, the contents are refreshed. All items with incomplete data resume download.


### Background

When running in the background, all running downloads continue on iOS 7 (and later). On iOS 6 all running downloads continue as background task for about 10 minutes.

### Network Interruption

When loosing network connection, all running downloads pause after request timeout. On iOS 7 (and later) the downloads resume when network becomes available again. On iOS 6 downloads are stopped after request timeout; they start again with the next app start.

## Timeout

There are two timeouts available: __request timeout__ and __resource timeout__.

The __request timeout__ fires "if no data is transmitted for the given timeout value, and is reset whenever data is transmitted". iOS's system default value is 60 seconds.

The __resource timeout__ (available with `NSURLSession`) fires "if a resource is not able to be retrieved within a given timeout". The resource timeout fires even if data is currently received. It is reset with the first download task resuming on a background session with no download tasks running. iOS's system default value is 604800 seconds (7 days).

If the host of the network request is not reachable, `NSURLConnection` checks for host availability right after request start and fails immediately with an error if the host is not reachable (NSURLErrorDomain Code=-1003 "A server with the specified hostname could not be found."). `NSURLSession` only terminates when the resource timeout fires.

## Integration

### Source Code Files

HWIFileDownload consists of these files:

* HWIBackgroundSessionCompletionHandlerBlock.h
* HWIFileDownloadDelegate.h
* HWIFileDownloader.h
* HWIFileDownloader.m
* HWIFileDownloadItem.h
* HWIFileDownloadItem.m
* HWIFileDownloadProgress.h
* HWIFileDownloadProgress.m

All files need to be added to the app project.

### App Delegate

See the sample code for advice on source code integration with the app delegate.

### Font Awesome

The demo app uses [Font Awesome](http://fontawesome.io "Font Awesome") for the download, cancel, pause, resume, completed, error, and cancelled icons.

