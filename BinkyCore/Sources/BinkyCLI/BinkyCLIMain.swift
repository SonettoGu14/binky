import BinkyCLILib
import Foundation

@main
enum BinkyCLIMain {
    static func main() {
        exit(Int32(BinkyCLIBootstrap.run(Array(CommandLine.arguments.dropFirst()))))
    }
}
