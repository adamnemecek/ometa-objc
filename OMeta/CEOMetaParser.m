//
//  CEOMetaParser.m
//  OMeta
//
//  Created by Chris Eidhof on 11/7/12.
//  Copyright (c) 2012 Chris Eidhof. All rights reserved.
//

#import "CEOMetaParser.h"
#import "CEOMetaAST.h"
#import "CETokens.h"

@interface CEOMetaParser () {
    id<CEOMetaTokenizer> tokenizer;
    NSArray* currentTokens;
}

@end

@implementation CEOMetaParser

- (id)initWithTokenizer:(id<CEOMetaTokenizer>)tokenizer_ {
    self = [super init];
    if(self) {
        tokenizer = tokenizer_;
    }
    return self;
}

- (id)parse:(NSString*)input {
    currentTokens = [tokenizer tokenize:input];
    [self keyword:@"ometa"];
    NSString* identifier = [self identifier];
    [self operator:@"{"];
    NSArray* currentState = currentTokens;
    id<CEObjCExp> code = nil;
    @try {
        code = [self parseCode];
    }
    @catch (NSException *exception) {
        currentTokens = currentState;
    }
    NSArray* rules = [self parseRules];
    [self operator:@"}"];
    CEOMetaProgram* p = [[CEOMetaProgram alloc] initWithName:identifier rules:rules];
    p.code = code;
    return p;
}

- (NSString*)identifier {
    id token = [self peek];
    if([token isKindOfClass:[CEKeywordToken class]]) {
        return [[self processNextToken] keyword];
    }
    [NSException raise:@"Expected identifier" format:@"Expected identifier, saw %@", token];
    return nil;
}

- (NSArray*)parseRules {
    return [self parseMany:@selector(parseRule) separatedBy:OP(@",")];
}

- (CEOMetaRule*)parseRule {
    NSString* ruleName = [self identifier];
    NSArray* args = [self parseMany:@selector(parseArg) separatedBy:nil];
    [self operator:@"="];
    id<CEOMetaExp> exp = [self parseExp];
    CEOMetaRule* rule = [[CEOMetaRule alloc] initWithName:ruleName body:exp];
    if(args.count) {
        rule.args = args;
    }
    return rule;
}

- (id<CEOMetaExp>)parseArg {
    id<CEOMetaExp> app = nil;
    @try {
        app = [self parseApp];
    }
    @catch (NSException *exception) {
    }
    [self operator:@":"];
    app =  app ? app : [[CEOMetaApp alloc] initWithName:@"anything"];
    NSString* ident = [self identifier];
    return [[CEOMetaNamed alloc] initWithName:ident
                                         body:app];

}

- (CEKeywordToken*)keyword:(NSString*)keyword {
    id token = [self peek];
    if([token isEqual:KEYWORD(keyword)]) {
        return [self processNextToken];
    }
    [NSException raise:@"Expected token" format:@"Expected keyword \"%@\", saw \"%@\", context: %@", keyword, token, currentTokens];
    return nil;
}

- (id<CEOMetaExp>)parseExp {
    return [self parseChoice];
}

// TODO: refactor parseChoice and parseSeq, they are the same
- (id<CEOMetaExp>)parseChoice {
    NSArray* currentState = currentTokens;
    
    @try {
        id<CEOMetaExp> lhs = [self parseAct];
        [self operator:@"|"];
        id<CEOMetaExp> rhs = [self parseChoice];
        return [[CEOMetaChoice alloc] initWithAlternative:lhs right:rhs];
    }
    @catch (NSException *exception) {
        currentTokens = currentState;
        return [self parseAct];
    }
}

- (id<CEOMetaExp>)parseAct {
    id<CEOMetaExp>left = [self parseSeq];
    NSArray* currentState = currentTokens;
    @try {
        id<CEObjCExp> condition = nil;
        @try {
            [self operator:@"?"];
            condition = [self parseObjCExpr];
            
        } @catch (NSException* e) {
        }
        [self operator:@"->"];
        id<CEObjCExp> act = [self parseObjCExpr];
        CEOMetaAct* result = [[CEOMetaAct alloc] initWithLeft:left act:act];
        result.condition = condition;
        return result;
    }
    @catch (NSException *exception) {
        currentTokens = currentState;
    }
    return left;
}

- (id<CEOMetaExp>)parseSeq {
    NSArray* currentState = currentTokens;
    @try {
        id<CEOMetaExp> lhs = [self parseNamed];
        id<CEOMetaExp> rhs = [self parseSeq];
        return [[CEOMetaSeq alloc] initWithLeft:lhs right:rhs];
    }
    @catch (NSException *exception) {
        currentTokens = currentState;
        return [self parseNamed];
    }
}

- (id<CEOMetaExp>)parseNamed {
    id<CEOMetaExp>body = [self parseMany];
    NSArray* currentState = currentTokens;
    @try {
        [self operator:@":"];
        NSString* name = [self identifier];
        return [[CEOMetaNamed alloc] initWithName:name body:body];
    }
    @catch (NSException *exception) {
        currentTokens = currentState;
    }
    return body;
}

- (id<CEOMetaExp>)parseMany {
    id<CEOMetaExp>left = [self parseManyOne];
    NSArray* currentState = currentTokens;
    @try {
        [self operator:@"*"];
        return [[CEOMetaRepeatMany alloc] initWithBody:left];
    }
    @catch (NSException *exception) {
        currentTokens = currentState;
    }
    return left;
}

- (id<CEOMetaExp>)parseManyOne {
    id<CEOMetaExp>left = [self parseNot];
    NSArray* currentState = currentTokens;
    @try {
        [self operator:@"+"];
        return [[CEOMetaRepeatOne alloc] initWithBody:left];
    }
    @catch (NSException *exception) {
        currentTokens = currentState;
    }
    return left;
}

- (id<CEOMetaExp>)parseNot {
    NSArray* currentState = currentTokens;
    @try {
        [self operator:@"~"];
        id<CEOMetaExp>body = [self parseParens];

        return [[CEOMetaNot alloc] initWithBody:body];
    }
    @catch (NSException *exception) {
        currentTokens = currentState;
        return [self parseParens];
    }
}

- (id<CEOMetaExp>)parseParens {
    NSArray* currentState = currentTokens;
    @try {
        [self operator:@"("];
        id<CEOMetaExp> exp = [self parseExp];
        [self operator:@")"];
        return exp;
    }
    @catch (NSException *exception) {
        currentTokens = currentState;
        return [self parseAtom];
    }
}

- (id<CEOMetaExp>)parseAtom {
    @try {
        return [self parseRuleApp];
    }
    @catch (NSException* e) {
    }
    @try {
        return [self parseApp];
    }
    @catch (NSException *exception) {
    }
    @try {
        return [self parseLiteral];
    }
    @catch (NSException* exception) {
    }
    return [self parseList];
}

- (id<CEOMetaExp>)parseList {
    [self operator:@"["];
    NSMutableArray* items = [NSMutableArray array];
    while(![[self peek] isEqual:OP(@"]")]) {
        [items addObject:[self parseExp]];
    }
    [self operator:@"]"];
    return [[CEOMetaList alloc] initWithItems:items];
}

- (id<CEOMetaExp>)parseLiteral {
    NSString* token = [self peek];
    if([token isKindOfClass:[CELiteralToken class]]) {
        CELiteralToken* token = [self processNextToken]; // pop the token
        return [[CEOMetaString alloc] initWithString:token.literal];
    }
    [NSException raise:@"Expected literal" format:@"Expected literal, saw \"%@\", context: %@", token, currentTokens];
    return nil;
}

- (id<CEOMetaExp>)parseRuleApp {
    NSString* ruleName = [self ruleAppToken];
    NSArray* args = [self parseMany:@selector(parseObjCExpr) separatedBy:OP(@",")];
    [self operator:@")"];
    return [[CEOMetaRuleApp alloc] initWithRuleName:ruleName args:args];
}

- (id<CEOMetaExp>)parseApp {
    NSString* token = [self identifier];
    return [[CEOMetaApp alloc] initWithName:token];
}

- (id<CEObjCExp>)parseObjCExpr {
    NSArray* tokens = currentTokens;
    @try {
        return [self parseCode];
    }
    @catch (NSException *exception) {
        currentTokens = tokens;
    }
    @try {
        return [self parseObjCIdentifier];
    }
    @catch (NSException *exception) {
        currentTokens = tokens;
    }
    @try {
        return [self parseObjCArrayLiteral];

    }
    @catch (NSException *exception) {
        currentTokens = tokens;
    }
    @try {
        return [self parseObjCMessage];
    }
    @catch (NSException *exception) {
        currentTokens = tokens;
    }
    @try {
        return [self parseObjCStringLiteral];
    }
    @catch (NSException *exception) {
        currentTokens = tokens;
    }
    return [self parseObjCBoxed];
}

- (id<CEObjCExp>)parseObjCBoxed {
    [self operator:@"@("];
    id<CEObjCExp> exp = [self parseObjCExpr];
    [self operator:@")"];
    return [[CEObjCBoxed alloc] initWithExp:exp];
}

- (id<CEObjCExp>)parseObjCMessage {
    [self operator:@"["];
    id<CEObjCExp> receiver = [self parseObjCExpr];
    NSArray* message = [self parseObjCMessageSelector];
    [self operator:@"]"];
    return [[CEObjCMessage alloc] initWithReceiver:receiver selector:message];
}

- (NSArray*)parseObjCMessageSelector {
    NSArray* tokens = currentTokens;
    @try {
        NSArray* keywordArguments = [self parseMany:@selector(parseObjCKeywordArgument) separatedBy:nil];
        if(keywordArguments.count == 0) [NSException raise:@"No keyword arguments" format:@"No keyword arguments"];
        return keywordArguments;
    }
    @catch (NSException *exception) {
        currentTokens = tokens;
    }
    return @[[self parseObjCIdentifier]];
}

- (id<CEObjCExp>)parseObjCKeywordArgument {
    id<CEObjCExp> keyword = [self parseObjCIdentifier];
    [self operator:@":"];
    id<CEObjCExp> exp = [self parseObjCExpr];
    return [[CEObjCKeywordArgument alloc] initWithKeyword:keyword exp:exp];
}

- (id<CEObjCExp>)parseObjCStringLiteral {
    NSString* token = [self peek];
    if([token isKindOfClass:[CEObjCStringLiteralToken class]]) {
        CEObjCStringLiteralToken* token = [self processNextToken];
        return [[CEObjCStringLiteral alloc] initWithString:token.string];
    }
    [NSException raise:@"Expected objc string literal" format:@"Expected objc string literal, saw \"%@\", context: %@", token, currentTokens];
    return nil;
}

- (id<CEObjCExp>)parseObjCIdentifier {
    NSString* identifier = [self identifier];
    return [[CEObjCIdentifier alloc] initWithIdentifierName:identifier];
}

- (id<CEObjCExp>)parseObjCArrayLiteral {
    [self operator:@"@["];
    
    NSArray* items = [self parseMany:@selector(parseObjCExpr) separatedBy:OP(@",")];
    [self operator:@"]"];
    return [[CEObjCArrayLiteral alloc] initWithExpressions:items];
}

- (id<CEObjCExp>)parseCode {
    id token = [self peek];
    if([token isKindOfClass:[CECodeToken class]]) {
        CECodeToken* codeToken = [self processNextToken];
        return [[CEObjCCodeBlock alloc] initWithCode:codeToken.code];
    }
    [NSException raise:@"Expected code block" format:@"Expected code block, saw \"%@\"", token];
    return nil;
}

- (NSString*)operator:(NSString*)operator {
    id token = [self peek];
    if([token isKindOfClass:[CEOperatorToken class]] && [[token operator] isEqualToString:operator]) {
        return [[self processNextToken] operator];
    }
    [NSException raise:@"Expected operator" format:@"Expected operator %@, saw \"%@\", context : %@", operator, token, currentTokens];
    return nil;
}

- (NSString*)ruleAppToken {
    id token = [self peek];
    if([token isKindOfClass:[CERuleApplicationToken class]]) {
        return [[self processNextToken] ruleName];
    }
    [NSException raise:@"Expected rule application" format:@"Expected rule application, saw \"%@\", context : %@", token, currentTokens];
    return nil;
}

#pragma mark Parser Combinators

- (NSArray*)parseMany:(SEL)elementParser separatedBy:(id)separator {
    NSArray* tokens = currentTokens;
    @try {
        id result = [self performSelector:elementParser];
        if([[self peek] isEqual:separator] || separator == nil) {
            if(separator) {
                [self processNextToken];
            }
            NSArray* rest = [self parseMany:elementParser separatedBy:separator];
            return [@[result] arrayByAddingObjectsFromArray:rest];
        } else {
            return @[result];
        }
    }
    @catch (NSException *exception) {
        currentTokens = tokens;
        return @[];
    }
    return @[];
}

- (NSString*)anything {
    return [self processNextToken];
}

- (NSString*)peek {
    if(currentTokens.count == 0) return nil;
    id token = currentTokens[0];
    return token;
}

- (id)processNextToken {
    if(currentTokens.count == 0) return nil;
    id token = currentTokens[0];
    currentTokens = [currentTokens subarrayWithRange:NSMakeRange(1, currentTokens.count-1)];
    return token;
}

@end