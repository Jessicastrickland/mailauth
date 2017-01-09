//
//	Copyright © 2012 - 2015 Roman Priebe
//
//	This file is part of M - Safe email made simple.
//
//	M is free software: you can redistribute it and/or modify
//	it under the terms of the GNU General Public License as published by
//	the Free Software Foundation, either version 3 of the License, or
//	(at your option) any later version.
//
//	M is distributed in the hope that it will be useful,
//	but WITHOUT ANY WARRANTY; without even the implied warranty of
//	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//	GNU General Public License for more details.
//
//	You should have received a copy of the GNU General Public License
//	along with M.  If not, see <http://www.gnu.org/licenses/>.
//





#import "NSAlert+AlertWithBlocks.h"

@implementation NSAlert (AlertWithBlocks)

-(void)legacyBeginSheetModalForWindow: (NSWindow *)sheetWindow
                        completionHandler: (void (^)(NSInteger returnCode))handler
{
    [self beginSheetModalForWindow: sheetWindow
                     modalDelegate: self
                    didEndSelector: @selector(blockAlertDidEnd:returnCode:contextInfo:)
                       contextInfo: (__bridge_retained void*)handler ];
}

-(void)blockAlertDidEnd: (NSAlert *)alert
                  returnCode: (NSInteger)returnCode
                 contextInfo: (void *)contextInfo
{
    void(^handler)(NSInteger) = (__bridge_transfer void(^)(NSInteger)) contextInfo;
    handler(returnCode);
}


@end
