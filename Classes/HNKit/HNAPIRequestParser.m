//
//  HNAPIRequestParser.m
//  newsyc
//
//  Created by Grant Paul on 3/12/11.
//  Copyright 2011 Xuzz Productions, LLC. All rights reserved.
//

#import "HNKit.h"
#import "HNAPIRequestParser.h"
#import "XMLDocument.h"
#import "XMLElement.h"
#import "NSString+Tags.h"

@implementation HNAPIRequestParser

- (NSDictionary *)parseUserProfileWithString:(NSString *)string {
    NSScanner *scanner = [NSScanner scannerWithString:string];
    NSString *key = nil, *value = nil;
    
    NSString *start = @"<tr><td valign=top>";
    NSString *mid = @":</td><td>";
    NSString *end = @"</td></tr>";
    
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    
    while ([scanner isAtEnd] == NO) {
        [scanner scanUpToString:start intoString:NULL];
        [scanner scanUpToString:mid intoString:&key];
        [scanner scanUpToString:end intoString:&value];
        if ([key hasPrefix:start]) key = [key substringFromIndex:[start length]];
        if ([value hasPrefix:mid]) value = [value substringFromIndex:[mid length]];
        
        if ([key isEqual:@"about"]) {
            [result setObject:value forKey:@"about"];
        } else if ([key isEqual:@"karma"]) {
            [result setObject:value forKey:@"karma"];
        } else if ([key isEqual:@"avg"]) {
            [result setObject:value forKey:@"average"];
        } else if ([key isEqual:@"created"]) {
            [result setObject:value forKey:@"created"];
        }
    }
    
    return result;
}

- (BOOL)rootElementIsSubmission:(XMLDocument *)document {
    return [document firstElementMatchingPath:@"//body/center/table/tr[3]/td/table//td[@class='title']"] != nil;
}

- (XMLElement *)rootElementForDocument:(XMLDocument *)document {
    if ([type isEqual:kHNPageTypeItemComments]) {
        return [document firstElementMatchingPath:@"//body/center/table/tr[3]/td/table[1]"];
    } else {
        return nil;
    }
}

- (NSArray *)contentRowsForDocument:(XMLDocument *)document {
    if ([type isEqual:kHNPageTypeActiveSubmissions] ||
        [type isEqual:kHNPageTypeAskSubmissions] ||
        [type isEqual:kHNPageTypeBestSubmissions] ||
        [type isEqual:kHNPageTypeClassicSubmissions] ||
        [type isEqual:kHNPageTypeSubmissions] ||
        [type isEqual:kHNPageTypeNewSubmissions] ||
        [type isEqual:kHNPageTypeBestComments] ||
        [type isEqual:kHNPageTypeNewComments]) {
        NSArray *elements = [document elementsMatchingPath:@"//body/center/table/tr[3]/td/table/tr"];
        return elements;
    } else if ([type isEqual:kHNPageTypeUserSubmissions] || 
               [type isEqual:kHNPageTypeUserComments]) {
        NSArray *elements = [document elementsMatchingPath:@"//body/center/table/tr"];
        return [elements subarrayWithRange:NSMakeRange(3, [elements count] - 5)];
    } else if ([type isEqual:kHNPageTypeItemComments]) {
        NSArray *elements = [document elementsMatchingPath:@"//body/center/table/tr[3]/td/table[2]/tr"];
        return elements;
    } else {
        return nil;
    }
}

- (NSDictionary *)parseSubmissionWithElements:(NSArray *)elements {
    XMLElement *first = [elements objectAtIndex:0];
    XMLElement *second = [elements objectAtIndex:1];
    XMLElement *fourth = nil;
    if ([elements count] >= 4) fourth = [elements objectAtIndex:3];
    
    // These have a number of edge cases (e.g. "discuss"),
    // so use sane default values in case of one of those.
    NSNumber *points = [NSNumber numberWithInt:0];
    NSNumber *comments = [NSNumber numberWithInt:0];
    
    NSString *title = nil;
    NSString *user = nil;
    NSNumber *identifier = nil;
    NSString *body = nil;
    NSString *date = nil;
    NSString *href = nil;
    
    for (XMLElement *element in [first children]) {
        if ([[element attributeWithName:@"class"] isEqual:@"title"]) {
            for (XMLElement *element2 in [element children]) {
                if ([[element2 tagName] isEqual:@"a"] && ![[element2 content] isEqual:@"scribd"]) {
                    title = [element2 content];
                    href = [element2 attributeWithName:@"href"];
                    
                    // In "ask HN" posts, we need to extract the id (and fix the URL) here.
                    if ([href hasPrefix:@"item?id="]) {
                        identifier = [NSNumber numberWithInt:[[href substringFromIndex:[@"item?id=" length]] intValue]];
                        href = nil;
                    }
                }
            }
        }
    }
    
    for (XMLElement *element in [second children]) {
        if ([[element attributeWithName:@"class"] isEqual:@"subtext"]) {
            NSString *content = [element content];
            
            // XXX: is there any better way of doing this?
            int start = [content rangeOfString:@"</a> "].location;
            if (start != NSNotFound) content = [content substringFromIndex:start + [@"</a> " length]];
            int end = [content rangeOfString:@" ago"].location;
            if (end != NSNotFound) date = [content substringToIndex:end];
            
            for (XMLElement *element2 in [element children]) {
                NSString *content = [element2 content];
                NSString *tag = [element2 tagName];
                
                if ([tag isEqual:@"a"]) {
                    if ([[element2 attributeWithName:@"href"] hasPrefix:@"user?id="]) {
                        user = [content stringByRemovingHTMLTags];
                        user = [user stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                    } else if ([[element2 attributeWithName:@"href"] hasPrefix:@"item?id="]) {
                        int end = [content rangeOfString:@" "].location;
                        if (end != NSNotFound) comments = [NSNumber numberWithInt:[[content substringToIndex:end] intValue]];
                        
                        identifier = [NSNumber numberWithInt:[[[element2 attributeWithName:@"href"] substringFromIndex:[@"item?id=" length]] intValue]];
                    }
                } else if ([tag isEqual:@"span"]) {
                    int end = [content rangeOfString:@" "].location;
                    if (end != NSNotFound) points = [NSNumber numberWithInt:[[content substringToIndex:end] intValue]];
                }
            }
        } else if ([[element attributeWithName:@"class"] isEqual:@"title"] && [[element content] isEqual:@"More"]) {
            // XXX: parse more link: [[element attributeWithName:@"href"] substringFromIndex:[@"x?fnid=" length]];
        }
    }
    
    for (XMLElement *element in [fourth children]) {
        if ([[element tagName] isEqual:@"td"]) {
            BOOL isReplyForm = NO;
            NSString *content = [element content];
            
            for (XMLElement *element2 in [element children]) {
                if ([[element2 tagName] isEqual:@"form"]) {
                    isReplyForm = YES;
                    break;
                }
            }
            
            if ([content length] > 0 && !isReplyForm) {
                body = content;
            }
        }
    }
    
    // XXX: better sanity checks?
    if (user != nil && title != nil && identifier != nil) {
        NSMutableDictionary *item = [NSMutableDictionary dictionary];
        [item setObject:user forKey:@"user"];
        [item setObject:points forKey:@"points"];
        [item setObject:title forKey:@"title"];
        [item setObject:comments forKey:@"numchildren"];
        if (href != nil) [item setObject:href forKey:@"url"];
        [item setObject:date forKey:@"date"];
        if (body != nil) [item setObject:body forKey:@"body"];
        [item setObject:identifier forKey:@"identifier"];
        return item;
    } else {
        NSLog(@"Bug: Ignoring unparsable submission (more link?).");
        return nil;
    }
}

- (NSDictionary *)parseCommentWithElement:(XMLElement *)comment {
    for (XMLElement *element in [comment children]) {
        if ([[element tagName] isEqual:@"tr"]) {
            comment = element;
            break;
        }
    }
    
    for (XMLElement *element in [comment children]) {
        if ([[element tagName] isEqual:@"td"]) {
            for (XMLElement *element2 in [element children]) {
                if ([[element2 tagName] isEqual:@"table"]) {
                    for (XMLElement *element3 in [element2 children]) {
                        if ([[element3 tagName] isEqual:@"tr"]) {
                            comment = element3;
                            goto found;
                        }
                    }
                }
            }
        }
    } found:;
    
    NSNumber *depth = nil;
    NSNumber *points = [NSNumber numberWithInt:0];
    NSString *body = nil;
    NSString *user = nil;
    NSNumber *identifier = nil;
    NSString *date = nil;
    
    for (XMLElement *element in [comment children]) {
        if ([[element attributeWithName:@"class"] isEqual:@"default"]) {
            for (XMLElement *element2 in [element children]) {
                if ([[element2 tagName] isEqual:@"div"]) {
                    for (XMLElement *element3 in [element2 children]) {
                        if ([[element3 attributeWithName:@"class"] isEqual:@"comhead"]) {
                            NSString *content = [element3 content];
                            
                            // XXX: is there any better way of doing this?
                            int start = [content rangeOfString:@"</a> "].location;
                            if (start != NSNotFound) content = [content substringFromIndex:start + [@"</a> " length]];
                            int end = [content rangeOfString:@" ago"].location;
                            if (end != NSNotFound) date = [content substringToIndex:end];
                            
                            for (XMLElement *element4 in [element3 children]) {
                                NSString *content = [element4 content];
                                NSString *tag = [element4 tagName];
                                
                                if ([tag isEqual:@"a"]) {
                                    NSString *href = [element4 attributeWithName:@"href"];
                                    
                                    if ([href hasPrefix:@"user?id="]) {
                                        user = [content stringByRemovingHTMLTags];
                                        user = [user stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                                    } else if ([href hasPrefix:@"item?id="] && [content isEqual:@"link"]) {
                                        identifier = [NSNumber numberWithInt:[[href substringFromIndex:[@"item?id=" length]] intValue]];
                                    }
                                } else if ([tag isEqual:@"span"]) {
                                    int end = [content rangeOfString:@" "].location;
                                    if (end != NSNotFound) points = [NSNumber numberWithInt:[[content substringToIndex:end] intValue]];
                                }
                            }
                        }
                    }
                } else if ([[element2 attributeWithName:@"class"] isEqual:@"comment"]) {
                    // XXX: strip out _reply_ link (or "----") at the bottom (when logged in), if necessary?
                    body = [element2 content];
                }
            }
        } else {
            for (XMLElement *element2 in [element children]) {
                if ([[element2 tagName] isEqual:@"img"] && [[element2 attributeWithName:@"src"] isEqual:@"http://ycombinator.com/images/s.gif"]) {
                    // Yes, really: HN uses a 1x1 gif to indent comments. It's like 1999 all over again. :(
                    int width = [[element2 attributeWithName:@"width"] intValue];
                    // Each comment is "indented" by setting the width to "depth * 40", so divide to get the depth.
                    depth = [NSNumber numberWithInt:(width / 40)];
                }
            }
        }
    }
    
    if (user == nil && [body isEqual:@"[deleted]"]) {
        // XXX: handle deleted comments
        NSLog(@"Bug: Ignoring deleted comment.");
        return nil;
    }
    
    // XXX: should this be more strict about what's a valid comment?
    if (user != nil && identifier != nil) {
        NSMutableDictionary *item = [NSMutableDictionary dictionary];
        [item setObject:user forKey:@"user"];
        if (body != nil) [item setObject:body forKey:@"body"];
        if (date != nil) [item setObject:date forKey:@"date"];
        if (points != nil) [item setObject:points forKey:@"points"];
        if (depth != nil) [item setObject:[NSMutableArray array] forKey:@"children"];
        if (depth != nil) [item setObject:depth forKey:@"depth"];
        [item setObject:identifier forKey:@"identifier"];
        
        return item;
    } else {
        NSLog(@"Bug: Unable to parse comment (more link?).");
        return nil;
    }
}

- (NSDictionary *)parseCommentTreeWithString:(NSString *)string {
    XMLDocument *document = [[XMLDocument alloc] initWithHTMLData:[string dataUsingEncoding:NSUTF8StringEncoding]];
    
    XMLElement *rootElement = [self rootElementForDocument:document];
    NSMutableDictionary *root = nil;
    if (rootElement != nil) {
        NSDictionary *item = nil;
        if ([self rootElementIsSubmission:document]) 
            item = [self parseSubmissionWithElements:[rootElement children]];
        else 
            item = [self parseCommentWithElement:[[rootElement children] objectAtIndex:0]];
        root = [[item mutableCopy] autorelease];
    }
    if (root == nil) root = [NSMutableDictionary dictionary];
    [root setObject:[NSMutableArray array] forKey:@"children"];
    
    NSArray *comments = [self contentRowsForDocument:document];
    NSMutableArray *lasts = [NSMutableArray array];
    [lasts addObject:root];
    
    for (int i = 0; i < [comments count]; i++) {
        XMLElement *element = [comments objectAtIndex:i];
        if ([[element content] length] == 0) continue;
        NSDictionary *comment = [self parseCommentWithElement:element];
        if (comment == nil) continue;
        
        NSDictionary *parent = nil;
        NSNumber *depth = [comment objectForKey:@"depth"];
        
        if (depth != nil) {
            if ([depth intValue] >= [lasts count]) continue;
            if ([lasts count] >= [depth intValue])
                [lasts removeObjectsInRange:NSMakeRange([depth intValue] + 1, [lasts count] - [depth intValue] - 1)];
            parent = [lasts lastObject];
            [lasts addObject:comment];
        } else {
            parent = root;
        }
        
        NSMutableArray *children = [parent objectForKey:@"children"];
        [children addObject:comment];
    }
    
    [document release];
    return root;
}

- (NSDictionary *)parseSubmissionsWithString:(NSString *)string {
    XMLDocument *document = [[XMLDocument alloc] initWithHTMLData:[string dataUsingEncoding:NSUTF8StringEncoding]];
    NSMutableArray *result = [NSMutableArray array];
    
    // The first row is the HN header, which also uses a nested table.
    // Hardcoding around it is required to prevent crashing.
    // XXX: can this be done in a more change-friendly way?
    NSArray *submissions = [document elementsMatchingPath:@"//table//tr[position()>1]//td//table//tr"];
    
    // Token for the next page of items.
    NSString *more = nil;
    
    // Three rows are used per submission.
    for (int i = 0; i + 2 < [submissions count]; i += 3) {
        XMLElement *first = [submissions objectAtIndex:i];
        XMLElement *second = [submissions objectAtIndex:i + 1];
        XMLElement *third = [submissions objectAtIndex:i + 2];
        
        NSDictionary *submission = [self parseSubmissionWithElements:[NSArray arrayWithObjects:first, second, third, nil]];
        if (submission != nil) [result addObject:submission];
    }
    
    [document release];
    
    NSMutableDictionary *item = [NSMutableDictionary dictionary];
    [item setObject:result forKey:@"children"];
    if (more != nil) [item setObject:more forKey:@"more"];
    return item;
}

- (id)initWithType:(HNPageType)type_ {
    if ((self = [super init])) {
        type = [type_ copy];
    }
    
    return self;
}

- (void)dealloc {
    [type release];
    [super dealloc];
}

@end
