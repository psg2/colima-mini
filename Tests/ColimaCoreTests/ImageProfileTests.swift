import XCTest

@testable import ColimaCore

final class ImageProfileTests: XCTestCase {
    private func port(_ container: Int, _ proto: String = "tcp") -> PublishedPort {
        PublishedPort(hostPort: 40_000 + container, containerPort: container, protocolName: proto)
    }

    func testCategoriesComeFromTheRepositoryName() {
        let cases: [(String, ImageProfile.Category)] = [
            ("postgres:18", .database), ("eventos-postgres", .database),
            ("ghcr.io/org/app-postgres:1@sha256:abc", .database), ("redis:7-alpine", .cache),
            ("localstack/localstack:4.14.0", .cloud), ("sosedoff/pgweb", .webTool),
            ("nginx:alpine", .webServer), ("rabbitmq:3-management", .queue), ("alpine:3.22", .other),
            ("node:22", .runtime),
        ]
        for (image, category) in cases {
            XCTAssertEqual(ImageProfile(image: image).category, category, image)
        }
    }

    func testOnlyKnownWebPortsOpenInTheBrowser() {
        XCTAssertTrue(ImageProfile(image: "sosedoff/pgweb").opensInBrowser(port(8081)))
        XCTAssertTrue(ImageProfile(image: "nginx").opensInBrowser(port(80)))
        XCTAssertTrue(ImageProfile(image: "rabbitmq:3-management").opensInBrowser(port(15672)))
        XCTAssertFalse(ImageProfile(image: "rabbitmq:3-management").opensInBrowser(port(5672)))
        XCTAssertFalse(ImageProfile(image: "postgres:18").opensInBrowser(port(5432)))
        XCTAssertFalse(ImageProfile(image: "localstack/localstack").opensInBrowser(port(4566)))
        XCTAssertFalse(ImageProfile(image: "nginx").opensInBrowser(port(80, "udp")))
        XCTAssertFalse(ImageProfile(image: "myapp:dev").opensInBrowser(port(3000)))
    }
}
