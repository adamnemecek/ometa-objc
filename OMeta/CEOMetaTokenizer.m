//
//  CEOMetaTokenizer.m
//  OMeta
//
//  Created by Chris Eidhof on 11/7/12.
//  Copyright (c) 2012 Chris Eidhof. All rights reserved.
//

#import "CEOMetaTokenizer.h"
#import "NSArray+Extensions.h"
#import "CETokens.h"
#import "NSString+Extras.h"
#import "NSArray+Extensions.h"

@interface CEOMetaTokenizer () {
    NSScanner* scanner;
}

@end

@implementation CEOMetaTokenizer

- (NSArray*)tokenize:(NSString*)input {
    scanner = [NSScanner scannerWithString:input];
    scanner.charactersToBeSkipped = nil;
    NSMutableArray* tokens = [NSMutableArray array];
    while (![scanner isAtEnd]) {
        NSArray* nextTokens = [self parseTokens];
        if(nextTokens == nil) {
          [[NSException exceptionWithName:@"No tokens" reason:@"Couldn't parse the rest of the tokens" userInfo:nil] raise];
            return nil;
        }
        [tokens addObjectsFromArray:nextTokens];
    }
    return tokens;
}

- (NSArray*)parseTokens {
    NSArray* result = [self parseRuleAppOrKeyword];
    if(!result) result = [self parseComment];
    if(!result) result = [self parseLiteral];
    if(!result) result = [self parseCodeBlock];
    if(!result) result = [self parseOperators];
    
    [self whitespace];
    
    return result;
}

- (NSArray*)parseComment {
    if([scanner scanString:@"//" intoString:NULL]) {
        [scanner scanUpToString:@"\n" intoString:NULL];
        [scanner scanString:@"\n" intoString:NULL];
        return @[];
    }
    return nil;
}

- (NSArray*)parseRuleAppOrKeyword {
    NSArray* result = [self parseKeyword];
    if(result.count == 1 && [scanner scanString:@"(" intoString:NULL]) {
        CEKeywordToken* keyword = result[0];
        return @[RULEAPP(keyword.keyword)];
    }
    return result;
}

- (NSArray*)parseKeyword {
    NSString* keyword = nil;
    [scanner scanCharactersFromSet:[NSCharacterSet letterCharacterSet] intoString:&keyword];
    if (keyword) {
        return @[KEYWORD(keyword)];
    }
    return nil;
}

- (NSString*)parseQuoted:(NSString*)quoteType {
    NSCharacterSet* quoteOrBackslash = [NSCharacterSet characterSetWithCharactersInString:[NSString stringWithFormat:@"%@\\", quoteType]];
    NSCharacterSet* other = [quoteOrBackslash invertedSet];
    NSMutableString* result = [NSMutableString string];
    NSString* literal = nil;
    BOOL done = NO;
    while(!done) {
        if([scanner scanCharactersFromSet:other intoString:&literal]) {
            [result appendString:literal];
        }
        else if([scanner scanString:@"\\" intoString:NULL]) {
            if([scanner scanString:quoteType intoString:NULL]) {
                [result appendString:quoteType];
            } else {
                [result appendString:@"\\"];
            }
        }
        else if([scanner scanString:quoteType intoString:NULL]) {
            done = YES;
        } else {
            assert(NO);
        }
    }
    return result;
}

- (NSArray*)parseLiteral {
    if([scanner scanString:@"'" intoString:NULL]) {
        NSString* result = [self parseQuoted:@"'"];
        return @[LIT(result)];
    } else if([scanner scanString:@"\"" intoString:NULL]) {
        NSString* result = [self parseQuoted:@"\""];
        return [[result components] map:^id(id obj) {
            return LIT(obj);
        }];
    } else if([scanner scanString:@"@\"" intoString:NULL]) {
        NSString* result = [self parseQuoted:@"\""];
        return @[OBJC_STRING_LIT(result)];
    }
    return nil;
}

- (void)whitespace {
    [scanner scanCharactersFromSet:[NSCharacterSet whitespaceAndNewlineCharacterSet] intoString:NULL];
}

- (NSArray*)parseCodeBlock {
    NSString* openCodeBlock = @"{{{";
    NSString* closeCodeBlock = @"}}}";
    if([scanner scanString:openCodeBlock intoString:NULL]) {
        NSString* code;
        if([scanner scanUpToString:closeCodeBlock intoString:&code]) {
            [scanner scanString:closeCodeBlock intoString:NULL];
            if(code) {
                return @[[CECodeToken code:code]];
            }
        }
    }
    return nil;
}

- (NSArray*)parseOperators {
    NSString* operator = nil;
    [scanner scanCharactersFromSet:[NSCharacterSet characterSetWithCharactersInString:@"[]()=+*?:|,~"] intoString:&operator];
    if(operator) {
        return [[operator components] map:^id(id obj) {
            return [CEOperatorToken operator:obj];
        }];
    }
    // We scan { and } separately so there's no confusion with {{{ and }}}
    NSArray* otherTokens = @[@"->", @"{", @"}", @"@[", @"@("];
    for(NSString* token in otherTokens) {
        [scanner scanString:token intoString:&operator];
        if(operator) {
            return @[[CEOperatorToken operator:operator]];
        }
        
    }
    return nil;
}

@end
