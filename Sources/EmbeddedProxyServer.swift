import Foundation
@preconcurrency import NIOCore
@preconcurrency import NIOHTTP1
@preconcurrency import NIOPosix

final class EmbeddedProxyServer {
    private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    private var channel: Channel?

    var isRunning: Bool {
        channel?.isActive == true
    }

    func start(router: OpenAICompatRouter, preferredPort: Int = 8000) throws -> Int {
        if isRunning {
            throw ProxyError.server("Proxy is already running.")
        }

        var lastError: Error?
        for port in preferredPort...8099 {
            do {
                let bootstrap = ServerBootstrap(group: group)
                    .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
                    .childChannelInitializer { channel in
                        channel.pipeline.configureHTTPServerPipeline(withErrorHandling: true).flatMap {
                            channel.pipeline.addHandler(LocalHTTPHandler(router: router))
                        }
                    }
                    .childChannelOption(.socketOption(.so_reuseaddr), value: 1)
                    .childChannelOption(.maxMessagesPerRead, value: 1)

                channel = try bootstrap.bind(host: "127.0.0.1", port: port).wait()
                return port
            } catch {
                lastError = error
            }
        }

        throw ProxyError.server("No available local proxy port from 8000 to 8099. \(lastError?.localizedDescription ?? "")")
    }

    func stop() {
        if let channel {
            try? channel.close().wait()
        }
        channel = nil
    }

    deinit {
        stop()
        try? group.syncShutdownGracefully()
    }
}

final class LocalHTTPHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let router: OpenAICompatRouter
    private var requestHead: HTTPRequestHead?
    private var requestBody: ByteBuffer?

    init(router: OpenAICompatRouter) {
        self.router = router
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch Self.unwrapInboundIn(data) {
        case .head(let head):
            requestHead = head
            requestBody = context.channel.allocator.buffer(capacity: 0)
        case .body(var chunk):
            requestBody?.writeBuffer(&chunk)
        case .end:
            guard let head = requestHead else {
                write(.text(status: 400, "Bad request."), version: .http1_1, context: context)
                return
            }
            let body = requestBody.map { Data($0.readableBytesView) } ?? Data()

            let contextBox = UnsafeContextBox(context)
            let promise = context.eventLoop.makePromise(of: ProxyHTTPResponse.self)
            promise.futureResult.whenComplete { result in
                let response: ProxyHTTPResponse
                switch result {
                case .success(let value):
                    response = value
                case .failure(let error):
                    response = .json(status: 500, ["error": ["message": error.localizedDescription]])
                }
                self.write(response, version: head.version, context: contextBox.context)
            }

            Task { [router, promise] in
                let response = await router.handle(
                    method: head.method,
                    uri: head.uri,
                    headers: head.headers,
                    body: body
                )
                promise.succeed(response)
            }
        }
    }

    private func write(_ response: ProxyHTTPResponse, version: HTTPVersion, context: ChannelHandlerContext) {
        var headers = HTTPHeaders()
        response.headers.forEach { headers.add(name: $0.0, value: $0.1) }
        headers.replaceOrAdd(name: "Content-Length", value: "\(response.body.count)")
        headers.replaceOrAdd(name: "Connection", value: "close")

        let status = HTTPResponseStatus(statusCode: response.status)
        let head = HTTPResponseHead(version: version, status: status, headers: headers)
        context.write(Self.wrapOutboundOut(.head(head)), promise: nil)

        var buffer = context.channel.allocator.buffer(capacity: response.body.count)
        buffer.writeBytes(response.body)
        context.write(Self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        context.writeAndFlush(Self.wrapOutboundOut(.end(nil)), promise: nil)
        context.close(promise: nil)
    }
}

private final class UnsafeContextBox: @unchecked Sendable {
    let context: ChannelHandlerContext

    init(_ context: ChannelHandlerContext) {
        self.context = context
    }
}
