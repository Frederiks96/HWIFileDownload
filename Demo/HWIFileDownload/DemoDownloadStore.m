/*
 * Project: HWIFileDownload (Demo App)
 
 * Created by Heiko Wichmann (20141004)
 * File: DemoDownloadStore.m
 *
 */

/***************************************************************************
 
 Copyright (c) 2014-2016 Heiko Wichmann
 
 https://github.com/Heikowi/HWIFileDownload
 
 This software is provided 'as-is', without any expressed or implied warranty.
 In no event will the authors be held liable for any damages
 arising from the use of this software.
 
 Permission is granted to anyone to use this software for any purpose,
 including commercial applications, and to alter it and redistribute it
 freely, subject to the following restrictions:
 
 1. The origin of this software must not be misrepresented;
 you must not claim that you wrote the original software.
 If you use this software in a product, an acknowledgment
 in the product documentation would be appreciated
 but is not required.
 
 2. Altered source versions must be plainly marked as such,
 and must not be misrepresented as being the original software.
 
 3. This notice may not be removed or altered from any source distribution.
 
 ***************************************************************************/


#import "DemoDownloadStore.h"
#import "DemoAppDelegate.h"
#import "DemoDownloadItem.h"
#import "DemoDownloadNotifications.h"
#import "HWIFileDownloader.h"

#import <UIKit/UIKit.h>


static void *DemoDownloadStoreProgressObserverContext = &DemoDownloadStoreProgressObserverContext;


@interface DemoDownloadStore()
@property (nonatomic, assign) NSUInteger networkActivityIndicatorCount;
@property (nonatomic, strong, readwrite, nonnull) NSMutableArray<DemoDownloadItem *> *downloadItemsArray;
@property (nonatomic, strong, nonnull) NSProgress *progress;
@end



@implementation DemoDownloadStore


- (nullable DemoDownloadStore *)init
{
    self = [super init];
    if (self)
    {
        self.networkActivityIndicatorCount = 0;
        
        self.progress = [NSProgress progressWithTotalUnitCount:0];
        if (floor(NSFoundationVersionNumber) > NSFoundationVersionNumber_iOS_6_1)
        {
            [self.progress addObserver:self
                            forKeyPath:NSStringFromSelector(@selector(fractionCompleted))
                               options:NSKeyValueObservingOptionInitial
                               context:DemoDownloadStoreProgressObserverContext];
        }
        
        [self setupDownloadItems];
    }
    return self;
}


- (void)setupDownloadItems
{
    self.downloadItemsArray = [self restoredDownloadItems];
    
    // setup items to download
    for (NSUInteger aDownloadIdentifierUInteger = 1; aDownloadIdentifierUInteger < 11; aDownloadIdentifierUInteger++)
    {
        NSString *aDownloadIdentifier = [NSString stringWithFormat:@"%@", @(aDownloadIdentifierUInteger)];
        NSUInteger aFoundDownloadItemIndex = [self.downloadItemsArray indexOfObjectPassingTest:^BOOL(DemoDownloadItem *aDemoDownloadItem, NSUInteger anIndex, BOOL *aStopFlag) {
            if ([aDemoDownloadItem.downloadIdentifier isEqualToString:aDownloadIdentifier])
            {
                return YES;
            }
            return NO;
        }];
        if (aFoundDownloadItemIndex == NSNotFound)
        {
            NSURL *aRemoteURL = [NSURL URLWithString:[NSString stringWithFormat:@"http://www.imagomat.de/testimages/%@.tiff", @(aDownloadIdentifierUInteger)]];
            DemoDownloadItem *aDemoDownloadItem = [[DemoDownloadItem alloc] initWithDownloadIdentifier:aDownloadIdentifier remoteURL:aRemoteURL];
            [self.downloadItemsArray addObject:aDemoDownloadItem];
        }
    };
    
    self.downloadItemsArray = [[self.downloadItemsArray sortedArrayUsingComparator:^NSComparisonResult(DemoDownloadItem*  _Nonnull aDownloadItemA, DemoDownloadItem*  _Nonnull aDownloadItemB) {
        return [aDownloadItemA.downloadIdentifier compare:aDownloadItemB.downloadIdentifier options:NSNumericSearch];
    }] mutableCopy];
}


- (void)dealloc
{
    if (floor(NSFoundationVersionNumber) > NSFoundationVersionNumber_iOS_6_1)
    {
        [self.progress removeObserver:self
                           forKeyPath:NSStringFromSelector(@selector(fractionCompleted))
                              context:DemoDownloadStoreProgressObserverContext];
    }
}


#pragma mark - HWIFileDownloadDelegate


- (void)downloadDidCompleteWithIdentifier:(nonnull NSString *)aDownloadIdentifier
                             localFileURL:(nonnull NSURL *)aLocalFileURL
{
    NSUInteger aFoundDownloadItemIndex = [self.downloadItemsArray indexOfObjectPassingTest:^BOOL(DemoDownloadItem *aDemoDownloadItem, NSUInteger anIndex, BOOL *aStopFlag) {
        if ([aDemoDownloadItem.downloadIdentifier isEqualToString:aDownloadIdentifier])
        {
            return YES;
        }
        return NO;
    }];
    DemoDownloadItem *aCompletedDownloadItem = nil;
    if (aFoundDownloadItemIndex != NSNotFound)
    {
        NSLog(@"INFO: Download completed (id: %@) (%s, %d)", aDownloadIdentifier, __FILE__, __LINE__);
        
        aCompletedDownloadItem = [self.downloadItemsArray objectAtIndex:aFoundDownloadItemIndex];
        aCompletedDownloadItem.status = DemoDownloadItemStatusCompleted;
        [self.downloadItemsArray replaceObjectAtIndex:aFoundDownloadItemIndex withObject:aCompletedDownloadItem];
        [self storeDownloadItems];
    }
    else
    {
        NSLog(@"ERR: Completed download item not found (id: %@) (%s, %d)", aDownloadIdentifier, __FILE__, __LINE__);
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:downloadDidCompleteNotification object:aCompletedDownloadItem];
}


- (void)downloadFailedWithIdentifier:(nonnull NSString *)aDownloadIdentifier
                               error:(nonnull NSError *)anError
                      httpStatusCode:(NSInteger)aHttpStatusCode
                  errorMessagesStack:(nullable NSArray *)anErrorMessagesStack
                          resumeData:(nullable NSData *)aResumeData
{
    NSUInteger aFoundDownloadItemIndex = [self.downloadItemsArray indexOfObjectPassingTest:^BOOL(DemoDownloadItem *aDemoDownloadItem, NSUInteger anIndex, BOOL *aStopFlag) {
        if ([aDemoDownloadItem.downloadIdentifier isEqualToString:aDownloadIdentifier])
        {
            return YES;
        }
        return NO;
    }];
    DemoDownloadItem *aFailedDownloadItem = nil;
    if (aFoundDownloadItemIndex != NSNotFound)
    {
        aFailedDownloadItem = [self.downloadItemsArray objectAtIndex:aFoundDownloadItemIndex];
        aFailedDownloadItem.lastHttpStatusCode = aHttpStatusCode;
        if (aFailedDownloadItem.status != DemoDownloadItemStatusPaused)
        {
            if ([anError.domain isEqualToString:NSURLErrorDomain] && (anError.code == NSURLErrorCancelled))
            {
                aFailedDownloadItem.status = DemoDownloadItemStatusCancelled;
            }
            else
            {
                aFailedDownloadItem.status = DemoDownloadItemStatusError;
                aFailedDownloadItem.downloadError = anError;
                aFailedDownloadItem.downloadErrorMessagesStack = anErrorMessagesStack;
            }
        }
        aFailedDownloadItem.resumeData = aResumeData;
        [self.downloadItemsArray replaceObjectAtIndex:aFoundDownloadItemIndex withObject:aFailedDownloadItem];
        [self storeDownloadItems];
    }
    else
    {
        NSLog(@"ERR: Failed download item not found (id: %@) (%s, %d)", aDownloadIdentifier, __FILE__, __LINE__);
    }
    if ([anError.domain isEqualToString:NSURLErrorDomain] && (anError.code == NSURLErrorCancelled))
    {
        NSLog(@"INFO: Download cancelled - id: %@ (%s, %d)", aDownloadIdentifier, __FILE__, __LINE__);
    }
    else
    {
        NSLog(@"ERR: %@ (%s, %d)", anError.localizedDescription, __FILE__, __LINE__);
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:downloadDidCompleteNotification object:aFailedDownloadItem];
}


- (void)downloadPausedWithIdentifier:(nonnull NSString *)aDownloadIdentifier
                          resumeData:(nullable NSData *)aResumeData
{
    NSUInteger aFoundDownloadItemIndex = [self.downloadItemsArray indexOfObjectPassingTest:^BOOL(DemoDownloadItem *aDemoDownloadItem, NSUInteger anIndex, BOOL *aStopFlag) {
        if ([aDemoDownloadItem.downloadIdentifier isEqualToString:aDownloadIdentifier])
        {
            return YES;
        }
        return NO;
    }];
    if (aFoundDownloadItemIndex != NSNotFound)
    {
        NSLog(@"INFO: Download paused - id: %@ (%s, %d)", aDownloadIdentifier, __FILE__, __LINE__);
        
        DemoDownloadItem *aPausedDownloadItem = [self.downloadItemsArray objectAtIndex:aFoundDownloadItemIndex];
        aPausedDownloadItem.status = DemoDownloadItemStatusPaused;
        aPausedDownloadItem.resumeData = aResumeData;
        [self.downloadItemsArray replaceObjectAtIndex:aFoundDownloadItemIndex withObject:aPausedDownloadItem];
        [self storeDownloadItems];
    }
    else
    {
        NSLog(@"ERR: Paused download item not found (id: %@) (%s, %d)", aDownloadIdentifier, __FILE__, __LINE__);
    }
}


- (void)downloadProgressChangedForIdentifier:(nonnull NSString *)aDownloadIdentifier
{
    NSUInteger aFoundDownloadItemIndex = [self.downloadItemsArray indexOfObjectPassingTest:^BOOL(DemoDownloadItem *aDemoDownloadItem, NSUInteger anIndex, BOOL *aStopFlag) {
        if ([aDemoDownloadItem.downloadIdentifier isEqualToString:aDownloadIdentifier])
        {
            return YES;
        }
        return NO;
    }];
    DemoDownloadItem *aChangedDownloadItem = nil;
    if (aFoundDownloadItemIndex != NSNotFound)
    {
        aChangedDownloadItem = [self.downloadItemsArray objectAtIndex:aFoundDownloadItemIndex];
        DemoAppDelegate *theAppDelegate = (DemoAppDelegate *)[UIApplication sharedApplication].delegate;
        HWIFileDownloadProgress *aFileDownloadProgress = [theAppDelegate.fileDownloader downloadProgressForIdentifier:aDownloadIdentifier];
        if (aFileDownloadProgress)
        {
            aChangedDownloadItem.progress = aFileDownloadProgress;
            if (floor(NSFoundationVersionNumber) > NSFoundationVersionNumber_iOS_6_1)
            {
                aChangedDownloadItem.progress.lastLocalizedDescription = aChangedDownloadItem.progress.nativeProgress.localizedDescription;
                aChangedDownloadItem.progress.lastLocalizedAdditionalDescription = aChangedDownloadItem.progress.nativeProgress.localizedAdditionalDescription;
            }
        }
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:downloadProgressChangedNotification object:aChangedDownloadItem];
}


- (void)incrementNetworkActivityIndicatorActivityCount
{
    [self toggleNetworkActivityIndicatorVisible:YES];
}


- (void)decrementNetworkActivityIndicatorActivityCount
{
    [self toggleNetworkActivityIndicatorVisible:NO];
}


- (BOOL)downloadAtLocalFileURL:(nonnull NSURL *)aLocalFileURL isValidForDownloadIdentifier:(nonnull NSString *)aDownloadIdentifier
{
    BOOL anIsValidFlag = YES;
    
    // just checking for file size
    // you might want to check by converting into expected data format (like UIImage) or by scanning for expected content
    
    NSError *anError = nil;
    NSDictionary <NSString *, id> *aFileAttributesDictionary = [[NSFileManager defaultManager] attributesOfItemAtPath:aLocalFileURL.path error:&anError];
    if (anError)
    {
        NSLog(@"ERR: Error on getting file size for item at %@: %@ (%s, %d)", aLocalFileURL, anError.localizedDescription, __FILE__, __LINE__);
        anIsValidFlag = NO;
    }
    else
    {
        unsigned long long aFileSize = [aFileAttributesDictionary fileSize];
        if (aFileSize == 0)
        {
            anIsValidFlag = NO;
        }
        else
        {
            if (aFileSize < 40000)
            {
                NSError *anError = nil;
                NSString *aString = [NSString stringWithContentsOfURL:aLocalFileURL encoding:NSUTF8StringEncoding error:&anError];
                if (anError)
                {
                    NSLog(@"ERR: %@ (%s, %d)", anError.localizedDescription, __FILE__, __LINE__);
                }
                else
                {
                    NSLog(@"INFO: Downloaded file content for download identifier %@: %@ (%s, %d)", aDownloadIdentifier, aString, __FILE__, __LINE__);
                }
                anIsValidFlag = NO;
            }
        }
    }
    return anIsValidFlag;
}


- (nullable NSProgress *)rootProgress
{
    if (floor(NSFoundationVersionNumber) > NSFoundationVersionNumber_iOS_6_1)
    {
        return self.progress;
    }
    else
    {
        return nil;
    }
}


#pragma mark - NSProgress KVO


- (void)observeValueForKeyPath:(nullable NSString *)aKeyPath
                      ofObject:(nullable id)anObject
                        change:(nullable NSDictionary<NSString*, id> *)aChange
                       context:(nullable void *)aContext
{
    if (aContext == DemoDownloadStoreProgressObserverContext)
    {
        NSProgress *aProgress = anObject; // == self.progress
        if ([aKeyPath isEqualToString:@"fractionCompleted"])
        {
            [[NSNotificationCenter defaultCenter] postNotificationName:totalDownloadProgressChangedNotification object:aProgress];
        }
        else
        {
            NSLog(@"ERR: Invalid keyPath (%s, %d)", __FILE__, __LINE__);
        }
    }
    else
    {
        [super observeValueForKeyPath:aKeyPath
                             ofObject:anObject
                               change:aChange
                              context:aContext];
    }
}


#pragma mark - Restart Download


- (void)restartDownload
{
    if (floor(NSFoundationVersionNumber) > NSFoundationVersionNumber_iOS_6_1)
    {
        [self.progress removeObserver:self forKeyPath:NSStringFromSelector(@selector(fractionCompleted))];
    }
    self.progress = [NSProgress progressWithTotalUnitCount:0];
    if (floor(NSFoundationVersionNumber) > NSFoundationVersionNumber_iOS_6_1)
    {
        [self.progress addObserver:self
                        forKeyPath:NSStringFromSelector(@selector(fractionCompleted))
                           options:NSKeyValueObservingOptionInitial
                           context:DemoDownloadStoreProgressObserverContext];
    }
    
    for (DemoDownloadItem *aDemoDownloadItem in self.downloadItemsArray)
    {
        if ((aDemoDownloadItem.status == DemoDownloadItemStatusPaused) || (aDemoDownloadItem.status == DemoDownloadItemStatusError))
        {
            [self startDownloadWithDownloadItem:aDemoDownloadItem];
        }
    }
    
    [self storeDownloadItems];
}


- (void)restartDownloadWithDownloadIdentifier:(nonnull NSString *)aDownloadIdentifier
{
    if (floor(NSFoundationVersionNumber) > NSFoundationVersionNumber_iOS_6_1)
    {
        [self.progress removeObserver:self forKeyPath:NSStringFromSelector(@selector(fractionCompleted))];
    }
    self.progress = [NSProgress progressWithTotalUnitCount:0];
    if (floor(NSFoundationVersionNumber) > NSFoundationVersionNumber_iOS_6_1)
    {
        [self.progress addObserver:self
                        forKeyPath:NSStringFromSelector(@selector(fractionCompleted))
                           options:NSKeyValueObservingOptionInitial
                           context:DemoDownloadStoreProgressObserverContext];
    }
    
    NSUInteger aFoundDownloadItemIndex = [self.downloadItemsArray indexOfObjectPassingTest:^BOOL(DemoDownloadItem *aDemoDownloadItem, NSUInteger anIndex, BOOL *aStopFlag) {
        if ([aDemoDownloadItem.downloadIdentifier isEqualToString:aDownloadIdentifier])
        {
            return YES;
        }
        return NO;
    }];
    if (aFoundDownloadItemIndex != NSNotFound)
    {
        DemoDownloadItem *aDemoDownloadItem = [self.downloadItemsArray objectAtIndex:aFoundDownloadItemIndex];
        [self startDownloadWithDownloadItem:aDemoDownloadItem];
    }
}


- (void)startDownloadWithDownloadItem:(nonnull DemoDownloadItem *)aDemoDownloadItem
{
    if ((aDemoDownloadItem.status != DemoDownloadItemStatusCancelled) && (aDemoDownloadItem.status != DemoDownloadItemStatusCompleted))
    {
        DemoAppDelegate *theAppDelegate = (DemoAppDelegate *)[UIApplication sharedApplication].delegate;
        BOOL isDownloading = [theAppDelegate.fileDownloader isDownloadingIdentifier:aDemoDownloadItem.downloadIdentifier];
        if (isDownloading == NO)
        {
            aDemoDownloadItem.status = DemoDownloadItemStatusStarted;
            
            // kick off individual download
            if (aDemoDownloadItem.resumeData.length > 0)
            {
                [theAppDelegate.fileDownloader startDownloadWithDownloadIdentifier:aDemoDownloadItem.downloadIdentifier usingResumeData:aDemoDownloadItem.resumeData];
            }
            else
            {
                [theAppDelegate.fileDownloader startDownloadWithDownloadIdentifier:aDemoDownloadItem.downloadIdentifier fromRemoteURL:aDemoDownloadItem.remoteURL];
            }
        }
    }
}



#pragma mark - Cancel Download


- (void)cancelDownloadWithDownloadIdentifier:(nonnull NSString *)aDownloadIdentifier
{
    NSUInteger aFoundDownloadItemIndex = [self.downloadItemsArray indexOfObjectPassingTest:^BOOL(DemoDownloadItem *aDemoDownloadItem, NSUInteger anIndex, BOOL *aStopFlag) {
        if ([aDemoDownloadItem.downloadIdentifier isEqualToString:aDownloadIdentifier])
        {
            return YES;
        }
        return NO;
    }];
    if (aFoundDownloadItemIndex != NSNotFound)
    {
        DemoDownloadItem *aCancelledDownloadItem = [self.downloadItemsArray objectAtIndex:aFoundDownloadItemIndex];
        aCancelledDownloadItem.status = DemoDownloadItemStatusCancelled;
        [self.downloadItemsArray replaceObjectAtIndex:aFoundDownloadItemIndex withObject:aCancelledDownloadItem];
        [self storeDownloadItems];
    }
    else
    {
        NSLog(@"ERR: Cancelled download item not found (id: %@) (%s, %d)", aDownloadIdentifier, __FILE__, __LINE__);
    }
}


#pragma mark - Network Activity Indicator


- (void)toggleNetworkActivityIndicatorVisible:(BOOL)visible
{
    visible ? self.networkActivityIndicatorCount++ : self.networkActivityIndicatorCount--;
    NSLog(@"INFO: NetworkActivityIndicatorCount: %@", @(self.networkActivityIndicatorCount));
    [UIApplication sharedApplication].networkActivityIndicatorVisible = (self.networkActivityIndicatorCount > 0);
}


#pragma mark - Persistence


- (void)storeDownloadItems
{
    NSMutableArray <NSData *> *aDemoDownloadItemsArchiveArray = [NSMutableArray arrayWithCapacity:self.downloadItemsArray.count];
    for (DemoDownloadItem *aDemoDownloadItem in self.downloadItemsArray)
    {
        NSData *aDemoDownloadItemEncoded = [NSKeyedArchiver archivedDataWithRootObject:aDemoDownloadItem];
        [aDemoDownloadItemsArchiveArray addObject:aDemoDownloadItemEncoded];
    }
    NSUserDefaults *userData = [NSUserDefaults standardUserDefaults];
    [userData setObject:aDemoDownloadItemsArchiveArray forKey:@"downloadItems"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}


- (nonnull NSMutableArray<DemoDownloadItem *> *)restoredDownloadItems
{
    NSMutableArray <DemoDownloadItem *> *aRestoredMutableDownloadItemsArray = [NSMutableArray array];
    NSMutableArray <NSData  *> *aRestoredMutableDataItemsArray = [[[NSUserDefaults standardUserDefaults] objectForKey:@"downloadItems"] mutableCopy];
    if (aRestoredMutableDataItemsArray == nil)
    {
        aRestoredMutableDataItemsArray = [NSMutableArray array];
    }
    for (NSData *aDataItem in aRestoredMutableDataItemsArray)
    {
        DemoDownloadItem *aDemoDownloadItem = [NSKeyedUnarchiver unarchiveObjectWithData:aDataItem];
        [aRestoredMutableDownloadItemsArray addObject:aDemoDownloadItem];
    }
    return aRestoredMutableDownloadItemsArray;
}

@end