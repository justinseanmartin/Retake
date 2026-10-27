// A take's own copy of the app's data, for its state:
//
//   clean   an empty home, with the set's files
//   cloned  an APFS clone of the real Documents and Library, with the set's files on top
//   live    the real home, with the set's files copied into it
//
// The take's home is <real home>/tmp/RetakeTakes/<RETAKE_TAKE>/, and the app is pointed at it by
// HOME, CFFIXED_USER_HOME and TMPDIR, which every standard folder lookup follows. Earlier takes'
// homes are deleted first, and the staged files once they're copied, since nothing on the Mac can
// delete files in the container.
#import "RetakeSupport.h"
#include <sys/clonefile.h>
#include <stdlib.h>

/// Copies every file under `from` to the same relative path under `to`, replacing what's there.
static void overlay(NSString *from, NSString *to) {
    NSFileManager *files = NSFileManager.defaultManager;
    for (NSString *relative in [files enumeratorAtPath:from]) {
        NSString *source = [from stringByAppendingPathComponent:relative];
        NSString *destination = [to stringByAppendingPathComponent:relative];
        BOOL isDirectory = NO;
        [files fileExistsAtPath:source isDirectory:&isDirectory];
        if (isDirectory) {
            [files createDirectoryAtPath:destination withIntermediateDirectories:YES attributes:nil error:nil];
        } else {
            [files createDirectoryAtPath:destination.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
            [files removeItemAtPath:destination error:nil];
            [files copyItemAtPath:source toPath:destination error:nil];
        }
    }
}

void RetakeSetUpState(NSDictionary<NSString *, NSString *> *environment) {
    NSString *state = environment[@"RETAKE_STATE"];
    NSFileManager *files = NSFileManager.defaultManager;
    NSString *staged = [RetakeRealHome stringByAppendingPathComponent:@"tmp/RetakeSet"];
    NSString *takes = [RetakeRealHome stringByAppendingPathComponent:@"tmp/RetakeTakes"];

    for (NSString *old in [files contentsOfDirectoryAtPath:takes error:nil]) {
        [files removeItemAtPath:[takes stringByAppendingPathComponent:old] error:nil];
    }

    if ([state isEqualToString:@"live"]) {
        overlay(staged, RetakeRealHome);
        [files removeItemAtPath:staged error:nil];
        return;
    }

    NSString *home = [takes stringByAppendingPathComponent:environment[@"RETAKE_TAKE"] ?: @"take"];
    [files createDirectoryAtPath:home withIntermediateDirectories:YES attributes:nil error:nil];
    if ([state isEqualToString:@"cloned"]) {
        for (NSString *name in @[@"Documents", @"Library"]) {
            NSString *source = [RetakeRealHome stringByAppendingPathComponent:name];
            NSString *destination = [home stringByAppendingPathComponent:name];
            if ([files fileExistsAtPath:source] && clonefile(source.fileSystemRepresentation, destination.fileSystemRepresentation, 0) != 0) {
                NSLog(@"[Retake] couldn't clone %@: %s", name, strerror(errno));
            }
        }
    }
    for (NSString *folder in @[@"Documents", @"Library/Caches", @"Library/Application Support", @"Library/Preferences", @"tmp"]) {
        [files createDirectoryAtPath:[home stringByAppendingPathComponent:folder] withIntermediateDirectories:YES attributes:nil error:nil];
    }
    overlay(staged, home);
    // Consumed, so that a take whose set has no files doesn't get the last take's: nothing on the
    // Mac can delete them.
    [files removeItemAtPath:staged error:nil];

    setenv("HOME", home.fileSystemRepresentation, 1);
    setenv("CFFIXED_USER_HOME", home.fileSystemRepresentation, 1);
    setenv("TMPDIR", [[home stringByAppendingPathComponent:@"tmp"] stringByAppendingString:@"/"].fileSystemRepresentation, 1);
}
