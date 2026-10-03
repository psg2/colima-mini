import Foundation

// What a container's image probably is, from its name alone. It picks an icon
// and decides whether a published port opens in the browser on click; ports
// are only treated as web pages for images known to serve one there.
package struct ImageProfile: Equatable {
    package enum Category: Equatable {
        case database, cache, search, queue, storage, cloud, webServer, webTool, runtime, other
    }
    package let category: Category
    // Container ports that serve a web page; empty means none, nil means any TCP port.
    package let webPorts: Set<Int>?

    package init(image: String) {
        let name = Self.repository(image)
        let words = Set(name.split(whereSeparator: { "-_./".contains($0) }).map(String.init))
        func any(_ candidates: [String]) -> Bool {
            candidates.contains { words.contains($0) || name == $0 }
        }

        if let (_, ports) = Self.webTools.first(where: { any([$0.0]) }) {
            category = .webTool
            webPorts = ports
        } else if any(["nginx", "httpd", "caddy", "traefik", "haproxy", "envoy", "apache"]) {
            category = .webServer
            webPorts = words.contains("traefik") ? [8080] : nil
        } else if any([
            "postgres", "postgresql", "postgis", "pgvector", "mysql", "mariadb", "mongo", "mongodb",
            "mssql", "sqlserver", "cockroach", "cockroachdb", "clickhouse", "cassandra", "timescaledb",
            "surrealdb", "neo4j", "couchdb",
        ]) {
            category = .database
            webPorts = words.contains("neo4j") ? [7474] : words.contains("couchdb") ? [5984] : []
        } else if any(["redis", "valkey", "memcached", "dragonfly", "keydb"]) {
            category = .cache
            webPorts = []
        } else if any(["elasticsearch", "opensearch", "meilisearch", "typesense", "solr"]) {
            category = .search
            webPorts = words.contains("meilisearch") ? [7700] : []
        } else if any(["rabbitmq", "kafka", "redpanda", "nats", "activemq", "pulsar"]) {
            category = .queue
            webPorts = words.contains("rabbitmq") ? [15672] : []
        } else if any(["minio", "azurite", "seaweedfs"]) {
            category = .storage
            webPorts = words.contains("minio") ? [9001] : []
        } else if any(["localstack", "gcloud", "firebase", "dynamodb"]) {
            category = .cloud
            webPorts = []
        } else if any(["node", "python", "ruby", "golang", "openjdk", "php", "deno", "bun", "dotnet"]) {
            category = .runtime
            webPorts = []
        } else {
            category = .other
            webPorts = []
        }
    }

    package func opensInBrowser(_ port: PublishedPort) -> Bool {
        guard port.protocolName == "tcp" else { return false }
        return webPorts.map { $0.contains(port.containerPort) } ?? true
    }

    private static let webTools: [(String, Set<Int>?)] = [
        ("pgweb", nil), ("adminer", nil), ("pgadmin4", nil), ("pgadmin", nil),
        ("phpmyadmin", nil), ("mongo-express", nil), ("redis-commander", nil),
        ("redisinsight", nil), ("grafana", [3000]), ("prometheus", [9090]), ("kibana", [5601]),
        ("jaeger", [16686]), ("all-in-one", [16686]), ("mailhog", [8025]), ("mailpit", [8025]),
        ("portainer", [9000, 9443]), ("metabase", [3000]), ("keycloak", [8080]),
        ("n8n", [5678]), ("swagger-ui", nil), ("dozzle", [8080]), ("uptime-kuma", [3001]),
    ]

    // `registry:5000/library/postgres:18@sha256:…` → `postgres`.
    private static func repository(_ image: String) -> String {
        var name = image.lowercased()
        if let digest = name.firstIndex(of: "@") { name = String(name[..<digest]) }
        if let slash = name.lastIndex(of: "/") { name = String(name[name.index(after: slash)...]) }
        if let tag = name.firstIndex(of: ":") { name = String(name[..<tag]) }
        return name
    }
}

extension Container {
    package var imageProfile: ImageProfile { ImageProfile(image: image) }
}
