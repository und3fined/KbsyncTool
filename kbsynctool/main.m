#import <stdio.h>
#import <Foundation/Foundation.h>
#import <libSandy.h>

#import "GCDWebServer.h"
#import "GCDWebServerDataResponse.h"
#import "GCDWebServerErrorResponse.h"

static id SandyGetJSONResponse(NSString *urlString, NSString *syncType)
{
    if (!libSandy_works()) {
        fprintf(stderr, "libSandy communication failed\n");
        return [NSDictionary dictionary];
    }

    xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_string(message, "url", [urlString UTF8String]);
    xpc_dictionary_set_string(message, "syncType", [syncType UTF8String]);

    xpc_object_t reply = sandydSendMessage(message);

    if (!reply) {
        fprintf(stderr, "Failed to get a reply\n");
        return [NSDictionary dictionary];
    }

    const char *jsonCString = xpc_dictionary_get_string(reply, "response");
    if (!jsonCString) {
        fprintf(stderr, "Invalid response\n");
        return [NSDictionary dictionary];
    }

    NSData *jsonData = [NSData dataWithBytes:jsonCString length:strlen(jsonCString)];
    return [NSJSONSerialization JSONObjectWithData:jsonData options:kNilOptions error:nil];
}

int main(int argc, char *argv[], char *envp[]) {

    if (argc != 2 && argc != 3) {
        fprintf(stderr, "usage: %s [url] [-p port]\n", argv[0]);
        return 1;
    }

    if (argc == 2) {
        // one-time execute
        NSString *urlString = [NSString stringWithUTF8String:argv[1]];
        id returnObj = SandyGetJSONResponse(urlString, @"base64");
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:returnObj options:(NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys) error:nil];
        NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];

        if (jsonString) {
            printf("%s\n", [jsonString UTF8String]);
        }

        return jsonString != nil ? 0 : 1;
    } else {
        // launch server
        NSInteger port = [[NSString stringWithUTF8String:argv[2]] integerValue];
        if (port <= 0 || port > 65535) {
            fprintf(stderr, "invalid server port\n");
            return 1;
        }

        GCDWebServer *webServer = [[GCDWebServer alloc] init];
        GCDWebServerAsyncProcessBlock webCallback = ^(GCDWebServerRequest *request, GCDWebServerCompletionBlock completionBlock) {
            NSString *urlString = [request query][@"url"];
            if (!urlString) {
                completionBlock([GCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_BadRequest message:@"invalid url"]);
                return;
            }

            id returnObj = SandyGetJSONResponse(urlString, @"hex");
            if (!returnObj) {
                completionBlock([GCDWebServerErrorResponse responseWithServerError:kGCDWebServerHTTPStatusCode_InternalServerError message:@"invalid url"]);
                return;
            }

            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:returnObj options:(NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys) error:nil];
            NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];

            if (jsonString) {
                NSLog(@"%@", jsonString);
            }

            completionBlock([GCDWebServerDataResponse responseWithData:jsonData contentType:@"application/json"]);
        };

        [webServer addDefaultHandlerForMethod:@"GET"
                                 requestClass:[GCDWebServerRequest class]
                            asyncProcessBlock:webCallback];
        [webServer addDefaultHandlerForMethod:@"POST"
                                 requestClass:[GCDWebServerRequest class]
                            asyncProcessBlock:webCallback];

        [webServer startWithPort:port bonjourName:nil];
        NSLog(@"Server started at %@", webServer.serverURL);

        CFRunLoopRun();
        return 0;
    }
}
