// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation
import ArgumentParser
import Blueprint 
import Syntax
import Thread

// MARK: - Configuration

enum Directories {
    static let content = URL(fileURLWithPath: "content", isDirectory: true)
    static let `static` = URL(fileURLWithPath: "static", isDirectory: true)
    static let styles = URL(fileURLWithPath: "styles", isDirectory: true)
    static let templates = URL(fileURLWithPath: "templates", isDirectory: true)
    static let output = URL(fileURLWithPath: "public", isDirectory: true)
}

enum ServerConfiguration {
    static let defaultPort: UInt16 = 8000
    static let indexFile = "index"
}

// MARK: - Errors

enum SiteError: Error, LocalizedError {
    case missingTemplate(String)
    case templateNotFound(String)
    case invalidMarkdown(URL)
    case fileSystemError(String)

    var errorDescription: String? {
        switch self {
        case .missingTemplate(let path): return "Missing template metadata in \(path)"
        case .templateNotFound(let path): return "Template not found: \(path)"
        case .invalidMarkdown(let url): return "Invalid Markdown file: \(url.path)"
        case .fileSystemError(let reason): return "File system error: \(reason)"
        }
    }
}

// MARK: - Data Models

struct Page {
    let url: String
    let title: String
    let metadata: [String: String]
    let content: String
    let relativePath: String

    init(from parsedContent: Markdown, relativePath: String) {
        self.relativePath = relativePath
        self.url = "/" + relativePath.replacingOccurrences(of: ".md", with: ".html")
        self.title = parsedContent.metadata["title"] ?? "Untitled"
        self.metadata = parsedContent.metadata
        self.content = parsedContent.html
    }

    var contextRepresentation: [String: Any] {
        [
            "url": url,
            "title": title,
            "metadata": metadata,
            "content": content
        ]
    }
}

// MARK: - File System Management

struct FileSystemManager {
    private static var fm: FileManager { .default }

    static func createDirectories(_ urls: [URL]) throws {
        for url in urls {
            try fm.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    static func recreateDirectory(_ url: URL) throws {
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
    }

    static func collectMarkdownFiles(in directoryURL: URL) throws -> [URL] {
        guard let enumerator = fm.enumerator(at: directoryURL,
                                             includingPropertiesForKeys: [.isRegularFileKey],
                                             options: [.skipsHiddenFiles]) else { return [] }

        return enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == "md" }
    }

    static func copyDirectory(from sourceURL: URL, to destinationURL: URL) throws {
        guard fm.fileExists(atPath: sourceURL.path) else { return }

        if let enumerator = fm.enumerator(at: sourceURL, includingPropertiesForKeys: nil) {
            for case let fileURL as URL in enumerator {
                let relative = fileURL.pathComponents.dropFirst(sourceURL.pathComponents.count).joined(separator: "/")
                let dest = destinationURL.appendingPathComponent(relative)

                if (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    try fm.createDirectory(at: dest, withIntermediateDirectories: true)
                } else {
                    let parent = dest.deletingLastPathComponent()
                    try fm.createDirectory(at: parent, withIntermediateDirectories: true)
                    if fm.fileExists(atPath: dest.path) {
                        try? fm.removeItem(at: dest)
                    }
                    try fm.copyItem(at: fileURL, to: dest)
                }
            }
        }
    }

    static func writeFile(content: String, to url: URL) throws {
        let dir = url.deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    static func fileExists(at path: String) -> Bool {
        fm.fileExists(atPath: path)
    }

    static func currentDirectoryPath() -> String {
        fm.currentDirectoryPath
    }
}

// MARK: - Path Helpers

struct PathResolver {
    static func getRelativePath(for fileURL: URL, from baseURL: URL) -> String {
        let base = baseURL.standardized.pathComponents
        let file = fileURL.standardized.pathComponents
        let relative = file.dropFirst(base.count).joined(separator: "/")
        return relative
    }

    static func isIndexPage(_ relativePath: String) -> Bool {
        relativePath == "index.md"
    }

    static func createOutputPath(from relativePath: String) -> URL {
        Directories.output
            .appendingPathComponent(relativePath)
            .deletingPathExtension()
            .appendingPathExtension("html")
    }
}

// MARK: - Templates

struct TemplateResolver {
    static func getTemplateURL(for parsedContent: Markdown, fileURL: URL) throws -> URL {
        guard let template = parsedContent.metadata["template"] else {
            throw SiteError.missingTemplate(fileURL.path)
        }

        let url = Directories.templates.appendingPathComponent(template)
        guard FileSystemManager.fileExists(at: url.path) else {
            throw SiteError.templateNotFound(url.path)
        }

        return url
    }
}

struct TemplateRenderer {
    static func render(templateContent: String, with context: [String: Any]) throws -> String {
        try Template(string: templateContent).render(Box(context))
    }
}

// MARK: - Content Parsing

struct ContentParser {
    private let parser = MarkdownParser()

    func parseMarkdown(from fileURL: URL) throws -> Markdown {
        do {
            let markdown = try String(contentsOf: fileURL)
            return parser.parse(markdown)
        } catch {
            throw SiteError.invalidMarkdown(fileURL)
        }
    }
}

struct PageCollector {
    private let parser = ContentParser()

    func collectAllPages(from files: [URL]) throws -> [Page] {
        try files.map { file in
            let parsed = try parser.parseMarkdown(from: file)
            let relative = PathResolver.getRelativePath(for: file, from: Directories.content)
            return Page(from: parsed, relativePath: relative)
        }
    }
}

// MARK: - Content Filtering

struct ContentFilter {
    static func getBlogPosts(from pages: [Page]) -> [[String: Any]] {
        let posts = pages.filter {
            $0.metadata["type"] == "post" || $0.relativePath.hasPrefix("blog/")
        }.sorted {
            if let a = $0.metadata["date"], let b = $1.metadata["date"] {
                return a > b
            }
            return $0.title < $1.title
        }

        return posts.map(\.contextRepresentation)
    }

    static func getAllPagesContext(from pages: [Page]) -> [[String: Any]] {
        pages.map(\.contextRepresentation)
    }
}

// MARK: - Context

struct ContextBuilder {
    static func buildContext(for parsed: Markdown, allPages: [Page] = [], isIndex: Bool = false) -> [String: Any] {
        var context: [String: Any] = ["content": parsed.html]
        parsed.metadata.forEach { context[$0] = $1 }

        if isIndex {
            context["pages"] = ContentFilter.getAllPagesContext(from: allPages)
            context["posts"] = ContentFilter.getBlogPosts(from: allPages)
        }

        return context
    }
}

// MARK: - Assets

struct AssetManager {
    static func copyAllAssets() throws {
        try FileSystemManager.copyDirectory(from: Directories.`static`, to: Directories.output)
        try FileSystemManager.copyDirectory(from: Directories.styles, to: Directories.output)
    }
}

// MARK: - Page Rendering

struct PageRenderer {
    private let parser = ContentParser()

    func renderPage(at url: URL, with allPages: [Page]) throws {
        let parsed = try parser.parseMarkdown(from: url)
        let templateURL = try TemplateResolver.getTemplateURL(for: parsed, fileURL: url)
        let templateContent = try String(contentsOf: templateURL)

        let relative = PathResolver.getRelativePath(for: url, from: Directories.content)
        let context = ContextBuilder.buildContext(for: parsed, allPages: allPages, isIndex: PathResolver.isIndexPage(relative))

        let rendered = try TemplateRenderer.render(templateContent: templateContent, with: context)
        let outputURL = PathResolver.createOutputPath(from: relative)
        try FileSystemManager.writeFile(content: rendered, to: outputURL)
    }
}

// MARK: - Site Builder

struct SiteBuilder {
    private let collector = PageCollector()
    private let renderer = PageRenderer()

    func build() throws {
        try FileSystemManager.recreateDirectory(Directories.output)
        try AssetManager.copyAllAssets()

        let files = try FileSystemManager.collectMarkdownFiles(in: Directories.content)
        let pages = try collector.collectAllPages(from: files)

        for file in files {
            try renderer.renderPage(at: file, with: pages)
        }

        print("✅ Build complete — \(files.count) pages processed.")
    }
}

// MARK: - Project Initialization

struct ProjectInitializer {
    static func createProjectStructure() throws {
        try FileSystemManager.createDirectories([
            Directories.content,
            Directories.`static`,
            Directories.styles,
            Directories.templates
        ])
        print("📁 Project directories created.")
    }
}

// MARK: - HTTP Server

struct StaticFileServer {
    private let server = HttpServer()
    private let publicPath: String

    init() {
        self.publicPath = FileSystemManager.currentDirectoryPath() + "/public"
    }

    func configureRoutes() {
        server.middleware.append { [publicPath] request in
            var path = request.path

            if path.isEmpty || path.hasSuffix("/") {
                path += ServerConfiguration.indexFile
            }

            if let htmlResponse = Self.tryServeHTML(path: path, root: publicPath) {
                return htmlResponse
            }

            if let staticResponse = Self.tryServeStatic(path: request.path, root: publicPath) {
                return staticResponse
            }

            return .notFound()
        }
    }

    private static func tryServeHTML(path: String, root: String) -> HttpResponse? {
        let fullPath = "\(root)\(path).html"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: fullPath)),
              let html = String(data: data, encoding: .utf8) else { return nil }
        return .ok(.html(html))
    }

    private static func tryServeStatic(path: String, root: String) -> HttpResponse? {
        let fullPath = root + path
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: fullPath)) else { return nil }
        return .raw(200, "OK", [:]) { writer in
            try writer.write(data)
        }
    }

    func start(on port: UInt16 = ServerConfiguration.defaultPort) throws {
        configureRoutes()
        print("🌍 Serving from: \(publicPath)")
        print("🚀 Visit: http://localhost:\(port)")
        try server.start(port)
        RunLoop.main.run()
    }
}

// MARK: - CLI

@main
struct Hypertext: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "hx",
        abstract: "An elegant static site generator",
        subcommands: [Init.self, Build.self, Serve.self]
    )
}

extension Hypertext {
    struct Init: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Create a new project structure.")
        func run() throws {
            try ProjectInitializer.createProjectStructure()
        }
    }

    struct Build: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Build the site into /public.")
        func run() throws {
            try SiteBuilder().build()
        }
    }

    struct Serve: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Serve the site locally after building.")
        func run() throws {
            try SiteBuilder().build()
            try StaticFileServer().start()
        }
    }
}
