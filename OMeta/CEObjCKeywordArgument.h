//
//  CEObjCKeywordArgument.h
//  OMeta
//
//  Created by Chris Eidhof on 11/25/12.
//  Copyright (c) 2012 Chris Eidhof. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CEObjCExp.h"

@interface CEObjCKeywordArgument : NSObject <CEObjCExp>

- (id)initWithKeyword:(id<CEObjCExp>)keyword exp:(id<CEObjCExp>)exp;

@end
