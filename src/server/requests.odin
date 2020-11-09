package server

import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:strings"
import "core:slice"
import "core:strconv"
import "core:encoding/json"

import "shared:common"


Header :: struct {
    content_length: int,
    content_type: string,
};

make_response_message :: proc(id: RequestId, params: ResponseParams) -> ResponseMessage {

    return ResponseMessage {
        jsonrpc = "2.0",
        id = id,
        result = params,
    };

}

make_response_message_error :: proc(id: RequestId, error: ResponseError) -> ResponseMessageError {

    return ResponseMessageError {
        jsonrpc = "2.0",
        id = id,
        error = error,
    };

}

read_and_parse_header :: proc(reader: ^Reader) -> (Header, bool) {

    header: Header;

    builder := strings.make_builder(context.temp_allocator);

    found_content_length := false;

    for true {

        strings.reset_builder(&builder);

        if !read_until_delimiter(reader, '\n', &builder) {
            log.error("Failed to read with delimiter");
            return header, false;
        }

        message := strings.to_string(builder);

        if len(message) == 0 || message[len(message)-2] != '\r' {
            log.error("No carriage return");
            return header, false;
        }

        if len(message)==2 {
            break;
        }

        index := strings.last_index_byte (message, ':');

        if index == -1 {
            log.error("Failed to find semicolon");
            return header, false;
        }

        header_name := message[0 : index];
        header_value := message[len(header_name) + 2 : len(message)-1];

        if strings.compare(header_name, "Content-Length") == 0 {

            if len(header_value) == 0 {
                log.error("Header value has no length");
                return header, false;
            }

            value, ok := strconv.parse_int(header_value);

            if !ok {
                log.error("Failed to parse content length value");
                return header, false;
            }

            header.content_length = value;

            found_content_length = true;

        }

        else if strings.compare(header_name, "Content-Type") == 0 {
            if len(header_value) == 0 {
                log.error("Header value has no length");
                return header, false;
            }
        }

    }

    return header, found_content_length;
}

read_and_parse_body :: proc(reader: ^Reader, header: Header) -> (json.Value, bool) {

    value: json.Value;

    data := make([]u8, header.content_length, context.temp_allocator);

    if !read_sized(reader, data) {
        log.error("Failed to read body");
        return value, false;
    }

    err: json.Error;

    value, err = json.parse(data = data, allocator = context.temp_allocator, parse_integers = true);

    if(err != json.Error.None) {
        log.error("Failed to parse body");
        return value, false;
    }

    return value, true;
}


handle_request :: proc(request: json.Value, config: ^common.Config, writer: ^Writer) -> bool {

    root, ok := request.value.(json.Object);

    if !ok  {
        log.error("No root object");
        return false;
    }

    id: RequestId;
    id_value: json.Value;
    id_value, ok = root["id"];

    if ok  {
        #partial
        switch v in id_value.value {
        case json.String:
            id = v;
        case json.Integer:
            id = v;
        case:
            id = 0;
        }
    }

    method := root["method"].value.(json.String);

    call_map : map [string] proc(json.Value, RequestId, ^common.Config, ^Writer) -> common.Error =
        {"initialize" = request_initialize,
         "initialized" = request_initialized,
         "shutdown" = request_shutdown,
         "exit" = notification_exit,
         "textDocument/didOpen" = notification_did_open,
         "textDocument/didChange" = notification_did_change,
         "textDocument/didClose" = notification_did_close,
         "textDocument/didSave" = notification_did_save,
         "textDocument/definition" = request_definition,
         "textDocument/completion" = request_completion,
         "textDocument/signatureHelp" = request_signature_help};

    fn: proc(json.Value, RequestId, ^common.Config, ^Writer) -> common.Error;
    fn, ok = call_map[method];


    if !ok {
        response := make_response_message_error(
                id = id,
                error = ResponseError {code = .MethodNotFound, message = ""}
            );

        send_error(response, writer);
    }

    else {
        err := fn(root["params"], id, config, writer);

        if err != .None {

            response := make_response_message_error(
                id = id,
                error = ResponseError {code = err, message = ""}
            );

            send_error(response, writer);
        }
    }

    return true;
}

request_initialize :: proc(params: json.Value, id: RequestId, config: ^common.Config, writer: ^Writer) -> common.Error {

    params_object, ok := params.value.(json.Object);

    if !ok {
        return .ParseError;
    }

    initialize_params: RequestInitializeParams;

    if unmarshal(params, initialize_params, context.temp_allocator) != .None {
        return  .ParseError;
    }

    config.workspace_folders = make([dynamic]common.WorkspaceFolder);

    for s in initialize_params.workspaceFolders {
        append_elem(&config.workspace_folders, s);
    }

    for format in initialize_params.capabilities.textDocument.hover.contentFormat {
        if format == .Markdown {
            config.hover_support_md = true;
        }
    }

    config.signature_offset_support = initialize_params.capabilities.textDocument.signatureHelp.signatureInformation.parameterInformation.labelOffsetSupport;


    completionTriggerCharacters := [] string { "." };
    signatureTriggerCharacters := [] string { "(" };

    response := make_response_message(
        params = ResponseInitializeParams {
            capabilities = ServerCapabilities {
                textDocumentSync = TextDocumentSyncOptions {
                    openClose = true,
                    change = 2, //incremental
                },
                definitionProvider = true,
                completionProvider = CompletionOptions {
                    resolveProvider = false,
                    triggerCharacters = completionTriggerCharacters,
                },
                signatureHelpProvider = SignatureHelpOptions {
                    triggerCharacters = signatureTriggerCharacters,
                },
            },
        },
        id = id,
    );

    send_response(response, writer);

    return .None;
}

request_initialized :: proc(params: json.Value, id: RequestId, config: ^common.Config, writer: ^Writer) -> common.Error {
    return .None;
}

request_shutdown :: proc(params: json.Value, id: RequestId, config: ^common.Config, writer: ^Writer) -> common.Error {

    response := make_response_message(
        params = nil,
        id = id,
    );

    send_response(response, writer);

    return .None;
}

request_definition :: proc(params: json.Value, id: RequestId, config: ^common.Config, writer: ^Writer) -> common.Error {

    params_object, ok := params.value.(json.Object);

    if !ok {
        return .ParseError;
    }

    definition_params: TextDocumentPositionParams;

    if unmarshal(params, definition_params, context.temp_allocator) != .None {
        return .ParseError;
    }


    document := document_get(definition_params.textDocument.uri);

    if document == nil {
        return .InternalError;
    }

    location, ok2 := get_definition_location(document, definition_params.position);

    if !ok2 {
        log.error("Failed to get definition location");
        return .InternalError;
    }

    response := make_response_message(
        params = location,
        id = id,
    );

    send_response(response, writer);


    return .None;
}


request_completion :: proc(params: json.Value, id: RequestId, config: ^common.Config, writer: ^Writer) -> common.Error {

    params_object, ok := params.value.(json.Object);

    if !ok {
        return .ParseError;
    }

    completition_params: CompletionParams;

    if unmarshal(params, completition_params, context.temp_allocator) != .None {
        return .ParseError;
    }


    document := document_get(completition_params.textDocument.uri);

    if document == nil {
        return .InternalError;
    }

    list: CompletionList;
    list, ok = get_completion_list(document, completition_params.position);

    if !ok {
        return .InternalError;
    }

    response := make_response_message(
        params = list,
        id = id,
    );

    send_response(response, writer);

    return .None;
}

request_signature_help :: proc(params: json.Value, id: RequestId, config: ^common.Config, writer: ^Writer) -> common.Error {

    params_object, ok := params.value.(json.Object);

    if !ok {
        return .ParseError;
    }

    signature_params: SignatureHelpParams;

    if unmarshal(params, signature_params, context.temp_allocator) != .None {
        return .ParseError;
    }

    document := document_get(signature_params.textDocument.uri);

    if document == nil {
        return .InternalError;
    }

    parameters := [] ParameterInformation {
        {
            label = {0, 4},
        },
    };


    signatures := [] SignatureInformation {
        {
            label = "test",
            parameters = parameters,
        },
    };

    help := SignatureHelp {
        activeSignature = 0,
        activeParameter = 0,
        signatures = signatures,
    };

    get_signature_information(document, signature_params.position);

    response := make_response_message(
        params = help,
        id = id,
    );

    send_response(response, writer);

    return .None;
}

notification_exit :: proc(params: json.Value, id: RequestId, config: ^common.Config, writer: ^Writer) -> common.Error {
    config.running = false;
    return .None;
}

notification_did_open :: proc(params: json.Value, id: RequestId, config: ^common.Config, writer: ^Writer) -> common.Error {

    params_object, ok := params.value.(json.Object);

    if !ok {
        log.error("Failed to parse open document notification");
        return .ParseError;
    }

    open_params: DidOpenTextDocumentParams;

    if unmarshal(params, open_params, context.allocator) != .None {
        log.error("Failed to parse open document notification");
        return .ParseError;
    }

    return document_open(open_params.textDocument.uri, open_params.textDocument.text, config, writer);
}

notification_did_change :: proc(params: json.Value, id: RequestId, config: ^common.Config, writer: ^Writer) -> common.Error {

    params_object, ok := params.value.(json.Object);

    if !ok {
        return .ParseError;
    }

    change_params: DidChangeTextDocumentParams;

    if unmarshal(params, change_params, context.temp_allocator) != .None {
        return .ParseError;
    }

    document_apply_changes(change_params.textDocument.uri, change_params.contentChanges, config, writer);

    return .None;
}

notification_did_close :: proc(params: json.Value, id: RequestId, config: ^common.Config, writer: ^Writer) -> common.Error {

    params_object, ok := params.value.(json.Object);

    if !ok {
        return .ParseError;
    }

    close_params: DidCloseTextDocumentParams;

    if unmarshal(params, close_params, context.temp_allocator) != .None {
        return .ParseError;
    }

    return document_close(close_params.textDocument.uri);
}

notification_did_save :: proc(params: json.Value, id: RequestId, config: ^common.Config, writer: ^Writer) -> common.Error {



    return .None;
}
