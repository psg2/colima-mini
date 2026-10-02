import XCTest

@testable import ColimaCore

final class EnvironmentTests: XCTestCase {
  func testCredentialsAreMaskedAndOrdinarySettingsAreNot() {
    let variables = EnvironmentVariable.parse([
      "POSTGRES_PASSWORD=hunter2", "AWS_SECRET_ACCESS_KEY=abc", "GITHUB_TOKEN=ghp_x",
      "STRIPE_API_KEY=sk", "DB_PASS=x", "JWT_PRIVATE_KEY=-----BEGIN",
      "SENTRY_DSN=https://k@o.ingest",
      "DATABASE_URL=postgres://app:s3cret@db:5432/app",
      "PATH=/usr/bin:/bin", "PGDATA=/var/lib/postgresql/data", "PWD=/app",
      "REDIS_URL=redis://cache:6379/0", "KEYBOARD_LAYOUT=us", "AUTHOR_NAME=me",
      "AUTH_HEADER=Bearer x", "LANG=C.UTF-8",
    ])
    let masked = Set(variables.filter(\.sensitive).map(\.name))
    XCTAssertEqual(
      masked,
      [
        "POSTGRES_PASSWORD", "AWS_SECRET_ACCESS_KEY", "GITHUB_TOKEN", "STRIPE_API_KEY", "DB_PASS",
        "JWT_PRIVATE_KEY", "SENTRY_DSN", "DATABASE_URL", "AUTH_HEADER",
      ])
  }

  func testValuesKeepEverythingAfterTheFirstEqualsSign() {
    XCTAssertEqual(
      EnvironmentVariable.parse(["OPTS=-Da=b -Dc=d", "EMPTY=", "BARE"]),
      [
        EnvironmentVariable(name: "OPTS", value: "-Da=b -Dc=d"),
        EnvironmentVariable(name: "EMPTY", value: ""),
        EnvironmentVariable(name: "BARE", value: ""),
      ])
  }
}
