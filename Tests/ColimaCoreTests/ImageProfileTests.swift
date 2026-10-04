import Foundation
import Testing

@testable import ColimaCore

struct ImageProfileTests {
    private func port(_ container: Int, _ proto: String = "tcp") -> PublishedPort {
        PublishedPort(hostPort: 40_000 + container, containerPort: container, protocolName: proto)
    }

    @Test func categoriesComeFromTheRepositoryName() {
        let cases: [(String, ImageProfile.Category)] = [
            ("postgres:18", .database), ("eventos-postgres", .database),
            ("ghcr.io/org/app-postgres:1@sha256:abc", .database), ("redis:7-alpine", .cache),
            ("localstack/localstack:4.14.0", .cloud), ("sosedoff/pgweb", .webTool),
            ("nginx:alpine", .webServer), ("rabbitmq:3-management", .queue), ("alpine:3.22", .other),
            ("node:22", .runtime),
        ]
        for (image, category) in cases {
            #expect(ImageProfile(image: image).category == category, "\(image)")
        }
    }

    @Test func onlyKnownWebPortsOpenInTheBrowser() {
        #expect(ImageProfile(image: "sosedoff/pgweb").opensInBrowser(port(8081)))
        #expect(ImageProfile(image: "nginx").opensInBrowser(port(80)))
        #expect(ImageProfile(image: "rabbitmq:3-management").opensInBrowser(port(15672)))
        #expect(!(ImageProfile(image: "rabbitmq:3-management").opensInBrowser(port(5672))))
        #expect(!(ImageProfile(image: "postgres:18").opensInBrowser(port(5432))))
        #expect(!(ImageProfile(image: "localstack/localstack").opensInBrowser(port(4566))))
        #expect(!(ImageProfile(image: "nginx").opensInBrowser(port(80, "udp"))))
        #expect(!(ImageProfile(image: "myapp:dev").opensInBrowser(port(3000))))
    }
}
