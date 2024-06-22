// swift-tools-version: 5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SupabaseRepository",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(name: "SupabaseRepository", targets: ["SupabaseRepository"])
    ],
    dependencies: [
        .package(url: "https://github.com/ivkuznetsov/Database.git", from: .init(1, 3, 6)),
        .package(url: "https://github.com/supabase-community/supabase-swift.git", from: .init(2, 5, 1)),
        .package(url: "https://github.com/ivkuznetsov/CommonUtils.git", from: .init(1, 2, 9)),
        .package(url: "https://github.com/onevcat/Kingfisher.git", from: .init(7, 11, 0)),
        .package(url: "https://github.com/ivkuznetsov/Loader.git", from: .init(1, 1, 0)),
        .package(url: "https://github.com/marmelroy/PhoneNumberKit.git", from: .init(3, 7, 10))
    ],
    targets: [
        .target(name: "SupabaseRepository", dependencies: ["Database", 
                                                           "CommonUtils",
                                                           "Kingfisher",
                                                           "Loader",
                                                           "PhoneNumberKit",
                                                           .product(name: "Supabase", package: "supabase-swift")])
    ]
)
