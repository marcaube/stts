#!/usr/bin/swift

import Foundation

struct AzureZone {
    let serviceName: String
    let zoneIdentifier: String

    var className: String {
        var sanitizedName = serviceName
        sanitizedName = sanitizedName.replacingOccurrences(of: " & ", with: "And")
        sanitizedName = sanitizedName.replacingOccurrences(of: "/", with: "")
        sanitizedName = sanitizedName.replacingOccurrences(of: ":", with: "")
        return sanitizedName.components(separatedBy: " ").map { $0.capitalized(firstLetterOnly: true) }.joined(separator: "")
    }

    init(identifier: String, serviceName: String) {
        zoneIdentifier = identifier

        if !serviceName.hasPrefix("Azure") {
            self.serviceName = "Azure \(serviceName)"
        } else {
            self.serviceName = serviceName
        }
    }

    var output: String {
        return """
        class \(className): Azure, SubService {
            let name = "\(serviceName)"
            let zoneIdentifier = "\(zoneIdentifier)"
        }
        """
    }
}

extension String {
    subscript(_ range: NSRange) -> String {
        // Why we still have to do this shit in 2019 I don't know
        let start = self.index(self.startIndex, offsetBy: range.lowerBound)
        let end = self.index(self.startIndex, offsetBy: range.upperBound)
        let subString = self[start..<end]
        return String(subString)
    }

    func capitalized(firstLetterOnly: Bool) -> String {
        return firstLetterOnly ? (prefix(1).capitalized + dropFirst()) : self
    }
}

func envVariable(forKey key: String) -> String {
    guard let variable = ProcessInfo.processInfo.environment[key] else {
        print("error: Environment variable '\(key)' not set")
        exit(1)
    }

    return variable
}

func discoverZones() -> [AzureZone] {
    var result = [AzureZone]()

    var dataResult: Data?

    let semaphore = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: URL(string: "https://status.azure.com/en-us/status")!) { data, _, _ in
        dataResult = data
        semaphore.signal()
    }.resume()

    _ = semaphore.wait(timeout: .now() + .seconds(10))

    guard let data = dataResult, var body = String(data: data, encoding: .utf8) else {
        print("warning: Build script generate_azure_services could not retrieve list of Azure zones")
        exit(0)
    }

    body = body.replacingOccurrences(of: "\n", with: "")

    // swiftlint:disable:next force_try
    let regex = try! NSRegularExpression(
        pattern: "li role=\"presentation\".*?data-zone-name=\"(.*?)\".*?data-event-property=\"(.*?)\"",
        options: [.caseInsensitive, .dotMatchesLineSeparators]
    )

    let range = NSRange(location: 0, length: body.count)
    regex.enumerateMatches(in: body, options: [], range: range) { textCheckingResult, _, _ in
        guard let textCheckingResult = textCheckingResult, textCheckingResult.numberOfRanges == 3 else { return }

        let identifier = body[textCheckingResult.range(at: 1)]
        let serviceName = body[textCheckingResult.range(at: 2)]

        result.append(AzureZone(identifier: identifier, serviceName: serviceName))
    }

    return result
}

func main() {
    let srcRoot = envVariable(forKey: "SRCROOT")
    let outputPath = "\(srcRoot)/stts/Services/Generated/AzureServices.swift"
    let zones = discoverZones()

    let header = """
    // This file is generated by generate_azure_services.swift and should not be modified manually.

    import Foundation

    """

    let content = zones.map { $0.output }.joined(separator: "\n\n")
    let footer = ""

    let output = [header, content, footer].joined(separator: "\n")

    // swiftlint:disable:next force_try
    try! output.write(toFile: outputPath, atomically: true, encoding: .utf8)

    print("Finished generating Azure services.")
}

main()
