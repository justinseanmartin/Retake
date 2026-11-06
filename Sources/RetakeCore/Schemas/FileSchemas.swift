/// Each kind of file's schema, written once here beside its reader, field for field: what the
/// reader accepts, described as the README and Documentation/cli.md describe it. `retake schema`
/// prints them and the reference is generated from them; a test fails when the checked-in copies
/// differ, and every file and example the tests read is checked against them.

// MARK: - retake.json

extension ProjectSettings {
    public static var schema: FileSchema {
        let path = "Relative to the directory holding retake.json."
        let scheme = Schema.object(
            "Retake builds a scheme with xcodebuild, for iOS devices, with its build products in the project's build folder.",
            [
                .init("scheme", .string("The scheme to build.", nonEmpty: true)),
                .init("workspace", .string("The workspace holding the scheme, needed only when the directory holds more than one. \(path)", nonEmpty: true)),
                .init("xcodeproj", .string("The project holding the scheme, needed only when the directory holds more than one. \(path)", nonEmpty: true)),
                .init("configuration", .string("The build configuration, which must be development-signed for the device.", nonEmpty: true).defaulting(to: "Debug")),
                .init("allowProvisioningUpdates", .bool("Lets xcodebuild register the device and update profiles on your team.").defaulting(to: false)),
                .init("optimize", .bool("Builds with the compiler's optimisation on, Swift at -O and C at -Os, whatever the configuration says, so the app runs as fast as its users see it.").defaulting(to: true)),
            ],
            required: ["scheme"],
        )
        let command = Schema.object(
            "The project's own command builds the app: for builds one xcodebuild call can't make. It's run with /bin/sh in the project's directory, with the device's UDID in RETAKE_DEVICE_UDID.",
            [
                .init("command", .string("The command that builds the app.", nonEmpty: true)),
                .init("app", .string("The .app the command leaves. \(path)", nonEmpty: true)),
            ],
            required: ["command", "app"],
        )
        let root = Schema.object(
            "A Retake project's configuration. Every field is optional.",
            [
                FileSchema.schemaKey,
                .init("bundleID", .string(
                    "The app's bundle ID. Without it, the bundle ID comes from the app `retake install` last embedded.",
                    pattern: #"^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*$"#,
                ).example("com.example.notes")),
                .init("build", .oneOf("How `retake install` builds the app when it isn't given one: a scheme, or a command of the project's own.", [scheme, command])),
                .init("device", .string("The device commands use when none is named: an alias, a UDID, or a device's name.", nonEmpty: true)),
                .init("defaultSet", .string("The set a scene starts on when it names none, and the one `retake compose` gives a new scene.", nonEmpty: true)),
                .init("output", .string("Where takes and cuts go. \(path)", nonEmpty: true).defaulting(to: "output")),
                .init("hitchWarning", .number(
                    "The milliseconds the app's main thread must miss frames for, at once, for `record` and `cut` to warn of it.", atLeast: 0,
                ).defaulting(to: .number(ProjectSettings.defaultHitchWarning))),
            ],
        )
        return FileSchema(kind: "retake", title: "retake.json", root: root, definitions: [])
    }
}

// MARK: - Sets

extension SetFile {
    public static var schema: FileSchema {
        var environmentName = Schema.string(nil, pattern: "^[A-Za-z_][A-Za-z0-9_]*$")
        environmentName.not = [.string(nil, pattern: "^(\(reservedEnvironmentPrefixes.joined(separator: "|")))")]
        let root = Schema.object(
            "A set: the state a take starts from — the app's data, its settings and its launch environment.",
            [
                FileSchema.schemaKey,
                .init("extends", .string("Another set this one builds on: its fields are laid under this set's.", nonEmpty: true)),
                .init("state", .choice(
                    "What the app's data starts as for a take, and whether the take's changes are kept. clean: empty but for the set's files and defaults. cloned: the app's real data with the set's on top, the take's changes thrown away. live: the real data, the take's changes kept.",
                    State.allCases.map(\.rawValue),
                ).defaulting(to: "clean")),
                .init("files", .dictionary(
                    "Files and folders put in the app's data before launch: each key is where it goes in the app's data, such as Documents/notes.json, and its value a path relative to the directory holding retake.json. The source may use .. to share fixtures outside the project. A folder ends in / on both sides.",
                    keys: .string(nil, pattern: "^[^/]"),
                    values: .string(nil, nonEmpty: true),
                ).example(.object(JSONObject([.init(key: "Documents/notes.sqlite", value: "data/returning-user/notes.sqlite")])))),
                .init("defaults", .dictionary(
                    "What UserDefaults.standard holds at launch: strings, numbers, booleans, and lists and dictionaries of them. null can't be stored.",
                    values: .anyValue(),
                )),
                .init("environment", .dictionary(
                    "Environment variables added to the launch, for the app's own flags. DYLD_, INSIDEJOB_ and RETAKE_ are Retake's own.",
                    keys: environmentName,
                    values: .string(),
                )),
                .init("arguments", .array("Arguments added to the launch, such as -AppleLanguages (en).", of: .string())),
                .init("previewAspect", .bool(
                    "Sizes the app's window to the App Store preview's shape for the device type recorded, 886:1920 on iPhone and 3:4 on iPad, turned in landscape; the edit crops away the rest of the screen. Otherwise the app fills the screen.",
                ).defaulting(to: false)),
                .init("appearance", .choice(
                    "Holds the app to light or dark, whatever the device is set to. The launch screen, drawn before the app runs, still follows the device.",
                    SetFile.Appearance.allCases.map(\.rawValue),
                )),
            ],
        )
        return FileSchema(kind: "set", title: "A set", root: root, definitions: [])
    }
}

// MARK: - Scenes

extension Schema {
    /// Points, or a percentage of `whole`, as a string: what `SceneFile.readLength` reads.
    static func length(_ description: String?, aboveZero: Bool = false, of whole: String = "the screen") -> Schema {
        .oneOf(description, [
            aboveZero ? .number(nil, above: 0) : .number(nil, atLeast: 0),
            .string("A percentage of \(whole), such as 50%.", pattern: #"^(100(\.0+)?|[0-9]{1,2}(\.[0-9]+)?)%$"#),
        ])
    }
}

extension SceneFile {
    public static var schema: FileSchema {
        let orientation = Schema.choice(nil, Orientation.allCases.map(\.rawValue))
        let point = Schema.object(nil, [
            .init("x", .length("Screen points from the left, or a percentage of the screen's width as the device faces.")),
            .init("y", .length("Screen points from the top, or a percentage of the screen's height as the device faces.")),
        ], required: ["x", "y"])
        let actions: [Schema.Property] = [
            .init("tap", .oneOf("Touches a point, x and y, or an element. An element is touched at its activation point, which the step log records, so either is drawn in the video.", [point, .ref("element")])),
            .init("drag", .object("A straight one-finger drag from one point or element to another. An element is touched at its activation point, as the screen has it just before the drag.", [
                .init("from", .oneOf("Where the finger comes down: a point, x and y, or an element.", [point, .ref("element")])),
                .init("to", .oneOf("Where it lifts: a point, x and y, or an element.", [point, .ref("element")])),
                .init("duration", .number("Seconds the drag takes.", above: 0).defaulting(to: .number(Step.defaultDragDuration))),
            ], required: ["from", "to"])),
            .init("type", .object("Types text key by key on the on-screen keyboard.", [
                .init("text", .string("What to type; \\n presses return.", nonEmpty: true)),
                .init("into", .ref("element", "The element to type into; the field already being typed in when not given.")),
            ], required: ["text"])),
            .init("activate", .ref("element", "An accessibility activation of an element, with no touch, for getting somewhere off camera.")),
            .init("orientation", orientation.described("Turns the device, with no hand on it; the step ends when the app has turned.")),
            .init("waitFor", Schema.object(
                "Waits until an element is on screen, or with gone until it isn't. The step fails if it doesn't happen in time.",
                elementProperties + [
                    .init("gone", .bool("Waits for the element to leave instead.").defaulting(to: false)),
                    .init("timeout", .number("Seconds to wait.", above: 0).defaulting(to: .number(Step.defaultWaitTimeout))),
                ],
            ).atLeastOne(of: ElementTarget.keys)),
        ]
        var holdOnly = Schema.object(nil, [], required: ["hold"])
        holdOnly.type = []
        holdOnly.not = [Schema().atLeastOne(of: Step.Action.keys)]
        var id = Schema.string(
            "The name edits anchor to. Unique in the scene; it can't look like a number, which anchors count steps by, nor be start or end.",
            nonEmpty: true,
        )
        id.not = [.choice(nil, ["start", "end"])]
        var step = Schema.object(
            "One thing the scene does, led by what it does, and the pause after it. A step can be only a hold.",
            actions + [
                .init("hold", .number("Seconds to pause after the step, or for a tap, from when it's sent; the scene's defaultHold when not given.", atLeast: 0)),
                .init("id", id),
            ],
        )
        step.oneOf = Step.Action.keys.map { key in var branch = Schema(); branch.required = [key]; return branch } + [holdOnly]

        let root = Schema.object(
            "A scene: a set, and the steps played on it.",
            [
                FileSchema.schemaKey,
                .init("set", .string("The set the scene starts on; the project's defaultSet when not given.", nonEmpty: true)),
                .init("setup", .array("Steps played before recording starts. Nothing anchors to them, so they have no id.", of: .ref("step"))),
                .init("leadIn", .number("Seconds recorded before the first step.", atLeast: 0).defaulting(to: .number(defaultLeadIn))),
                .init("tail", .number("Seconds recorded after the last step.", atLeast: 0).defaulting(to: .number(defaultTail))),
                .init("defaultHold", .number("The hold of each step that doesn't give its own.", atLeast: 0).defaulting(to: 0)),
                .init("recordsLaunch", .bool("Starts recording before the app launches, to catch its launch screen.").defaulting(to: false)),
                .init("orientation", orientation.described("The orientation the device is turned to before the app launches.").defaulting(to: "portrait")),
                .init("steps", .array("What the scene does, in order.", of: .ref("step"), minItems: 1)),
            ],
            required: ["steps"],
        )
        return FileSchema(kind: "scene", title: "A scene", root: root, definitions: [.init("step", step), .init("element", element)])
    }

    /// An element's properties, as a step, a spotlight or a blur names it.
    static var elementProperties: [Schema.Property] {
        [
            .init("label", .string("Its accessibility label.", nonEmpty: true)),
            .init("value", .string("Its value: a text field's placeholder, or what's typed in it.")),
            .init("identifier", .string("The accessibilityIdentifier the app gives it.", nonEmpty: true)),
            .init("hint", .string("Its accessibility hint: what VoiceOver says it does.", nonEmpty: true)),
            .init("traits", .array(
                "Traits it has, every one, by The Button Heist's names, as `retake compose` prints them.",
                of: .choice(nil, ElementTarget.knownTraits.sorted()), minItems: 1, unique: true,
            ).example(["header"], ["button", "selected"])),
            .init("occurrence", .integer("Which of several matching elements, counted from 1 in the order VoiceOver reads the screen. A last resort, since it breaks when the layout changes: name the element closely enough, by its traits, identifier, value or hint, that only it matches.", atLeast: 1)),
        ]
    }

    /// An element on screen, as VoiceOver knows it: by any of these, together.
    static var element: Schema {
        Schema.object("An element on screen, as VoiceOver knows it: by any of its label, value, identifier, hint and traits.", elementProperties)
            .atLeastOne(of: ElementTarget.keys)
    }
}

// MARK: - Edits

extension EditFile {
    public static var schema: FileSchema {
        let file = Schema.string("A sound file, relative to the directory holding retake.json.", nonEmpty: true)
        let volume = Schema.number("Its level, where 1 is as recorded.", atLeast: 0).defaulting(to: 1)
        let turns = Schema.choice(
            "How the video shows the device turning. letterboxed: the app stays upright, landscape letterboxed on the canvas. device: the video stays in the device's frame.",
            Edit.Turns.allCases.map(\.rawValue),
        )
        let region: [Schema.Property] = [
            .init("element", .ref("element", "An element, found in the take's step log at the moment.")),
            .init("part", .ref("part")),
            .init("rect", .ref("rect")),
        ]
        let from = Schema.ref("anchor", "When it starts; the clip's from when not given.")
        let to = Schema.ref("anchor", "When it ends; the clip's to when not given.")

        let stepReference = Schema.oneOf("A step's id, its number counted from 1, a negative number counting back from the last (-1 is the last), or start or end, the take's own first and last frames. Prefer the id, which survives steps being added to the scene.", [
            .string(nil, nonEmpty: true),
            { var number = Schema.integer(); number.not = [{ var zero = Schema(); zero.choices = [0]; return zero }()]; return number }(),
        ])
        let clip = Schema.object("A stretch of a take, played in order.", [
            .init("id", .string("Names the clip, for a caption to run on into it. Unique in the edit.", nonEmpty: true)),
            .init("intent", .string("What the clip is there to show, for whoever changes the video later. Not read by the render.")),
            .init("take", .string("The scene whose latest successful take the clip is cut from.", nonEmpty: true)),
            .init("from", .ref("anchor", "Where the clip starts in the take.")),
            .init("to", .ref("anchor", "Where it ends.")),
            .init("speed", .number("How fast it plays: 2 is twice as fast.", above: 0).defaulting(to: 1)),
            .init("crossfade", .number("Seconds it cross-fades in over the clip before.", atLeast: 0).defaulting(to: 0)),
            .init("audioCrossfade", .number("Seconds the sound cross-fades over, when longer than crossfade, which the picture still cross-fades over: the clip before's take sound fades out over this long before that clip ends, and this clip's starts as it does, this minus crossfade ahead of the picture and from as far before `from` in the take, fading in until the clip before ends. Each side fades so even when the other plays no take sound. The clip's sound starts no earlier than its take, or the clip before, does.", atLeast: 0)),
            .init("touches", .bool("Draws the take's touches, from the step log.").defaulting(to: true)),
            .init("touchColor", .ref("color", "The colour of the clip's touches; the edit's touchColor when not given.")),
            .init("touchColors", .array("Colours for single touches, over the clip's or the edit's.", of: .object(nil, [
                .init("step", stepReference),
                .init("color", .ref("color")),
            ], required: ["step", "color"]))),
            .init("takeAudio", .bool("Plays the take's own sound with the clip.").defaulting(to: false)),
            .init("captions", .array(nil, of: .ref("caption"))),
            .init("sounds", .array("Sound effects, played at normal speed however fast the clip plays.", of: .ref("sound"))),
            .init("spotlight", .ref("spotlight")),
            .init("blurs", .array("Blurs over a stretch of the take, for anything private it shows.", of: .ref("blur"))),
            .init("stills", .array("Frames of other takes, popped in over the clip.", of: .ref("still"))),
            .init("stillsOut", .ref("anchor", "When the stills pop out, one after another in the order they popped in; they stay to the clip's end when not given.")),
            .init("stillsBackground", .ref("color", "A colour filling the canvas behind the stills, fading in as the first pops in, so they stand on it rather than on the clip's picture.")),
            .init("card", .ref("card")),
            .init("devices", .array("The device types whose videos play it; every one of the edit's when not given.", of: .choice(nil, DeviceType.allCases.map(\.rawValue)), minItems: 1, unique: true)),
            .init("turns", turns.described("How this clip shows the device turning; the edit's turns when not given.")),
            .init("turnBlur", .ref("turn-blur")),
        ], required: ["take", "from", "to"])

        let caption = Schema.object("Text over the video, from its from to its to.", [
            .init("text", .string(nil, nonEmpty: true)),
            .init("y", .number("Its centre, as a share of the video's height: 0 at the top, 1 at the bottom.", atLeast: 0, atMost: 1)),
            .init("color", .ref("color")),
            .init("from", .ref("anchor", "When it starts; once its clip has faded in when not given.")),
            .init("to", .oneOf("When it ends: an anchor in its clip's take, or, naming a later clip, in that clip's take; as the next clip starts to fade in when not given.", [
                .ref("anchor"), .ref("caption-end"),
            ])),
            .init("symbol", .ref("symbol")),
        ], required: ["text", "y", "color"])

        var stepAnchor = Schema.object("A step, and where to go from it.", [
            .init("step", stepReference),
            .init("offset", .number("Seconds to move: forward from the step's end, or back from its start.")),
            .init("fraction", .number("A share of the gap to the neighbouring step to move: forward from the step's end toward the next step's start, or back from its start toward the previous step's end.", atLeast: -1, atMost: 1)),
            .init("edge", .choice("Counts the offset or fraction from the step's other edge.", Anchor.Edge.allCases.map(\.rawValue))),
        ], required: ["step"])
        stepAnchor.not = [{ var both = Schema(); both.required = ["offset", "fraction"]; return both }()]
        var captionEnd = stepAnchor
        captionEnd.description = "A later clip, by its id, and an anchor in that clip's take; as that clip's next starts to fade in, when it gives no step."
        captionEnd.properties.insert(.init("clip", .string("The later clip's id.", nonEmpty: true)), at: 0)
        captionEnd.required = ["clip"]

        let definitions: [Schema.Property] = [
            .init("clip", clip),
            .init("caption", caption),
            .init("symbol", .object("An SF Symbol before the caption's text.", [
                .init("name", .string("The symbol's name, such as rotate.right.", nonEmpty: true)),
                .init("animation", .ref("animation")),
            ], required: ["name"])),
            .init("animation", .object("How the symbol moves, from when the caption appears.", [
                .init("rotate", .ref("rotate")),
            ], required: ["rotate"])),
            .init("rotate", .object("Turns the symbol.", [
                .init("degrees", .number("Clockwise when positive.")),
                .init("duration", .number("Seconds it takes.", above: 0)),
            ], required: ["degrees", "duration"])),
            .init("card", .object("A colour covering the clip's picture, and everything drawn over it but its captions, for a card between clips: over the whole clip, fading in and out with the cross-fades either side, or from its from to its to.", [
                .init("color", .ref("color")),
                .init("from", .ref("anchor", "When it starts; the clip's from when not given.")),
                .init("to", .ref("anchor", "When it ends; the clip's to when not given.")),
            ], required: ["color"])),
            .init("sound", .object("A sound effect.", [
                .init("file", file),
                .init("at", .ref("anchor", "When it starts.")),
                .init("volume", volume),
                .init("duration", .number("Seconds it plays before fading out, for an effect longer than its moment; all of it when not given.", above: 0)),
            ], required: ["file", "at"])),
            .init("spotlight", Schema.object("Dims the rest of the screen around an element or a rectangle, with a pulsing ring.", region + [
                .init("padding", .number("Points of space around it.", atLeast: 0).defaulting(to: 8)),
                .init("color", .ref("color", "The ring's colour.").defaulting(to: "#FFFFFF")),
                .init("from", from), .init("to", to),
            ]).exactlyOne(of: ["element", "rect"])),
            .init("blur", Schema.object("A blur over an element or a rectangle.", region + [
                .init("from", from), .init("to", to),
                .init("radius", .number("How strong the blur is.", above: 0).defaulting(to: 20)),
            ]).exactlyOne(of: ["element", "rect"])),
            .init("still", .object("A frame of another take, popped in over the clip.", [
                .init("take", .string("The scene whose latest successful take it's from.", nonEmpty: true)),
                .init("at", .ref("anchor", "The moment in that take.")),
            ], required: ["take", "at"])),
            .init("rect", .object("A rectangle of the screen, each side in screen points or a percentage of the screen as the device faced.", [
                .init("x", .length(nil)), .init("y", .length(nil)),
                .init("width", .length(nil, aboveZero: true)), .init("height", .length(nil, aboveZero: true)),
            ], required: ["x", "y", "width", "height"])),
            .init("part", .object("Part of the element, each side in points from its top-left corner or a percentage of its frame; its whole frame on a side not given, as \"part\": { \"x\": \"62%\", \"width\": \"38%\" } is its right 38%.", [
                .init("x", .length(nil, of: "the element").defaulting(to: "0%")), .init("y", .length(nil, of: "the element").defaulting(to: "0%")),
                .init("width", .length(nil, aboveZero: true, of: "the element").defaulting(to: "100%")),
                .init("height", .length(nil, aboveZero: true, of: "the element").defaulting(to: "100%")),
            ])),
            .init("music", .object("Plays under the whole video.", [
                .init("file", file), .init("volume", volume),
                .init("fadeOut", .number("Seconds it fades out over at the end.", atLeast: 0).defaulting(to: 0)),
            ], required: ["file"])),
            .init("tap-sound", .object("Plays as each touch a clip draws lands: each tap by point, and the start of each drag.", [
                .init("file", file), .init("volume", volume),
            ], required: ["file"])),
            .init("turn-blur", .object("Blurs each turn, easing in just before it and out after.", [
                .init("duration", .number("Seconds the blur lasts.", above: 0)),
            ], required: ["duration"])),
            .init("anchor", .oneOf(
                "A moment in a take: a step and where to go from it, or plain seconds from the take's start.",
                [.number("Seconds from the take's start, which the first `retake cut` turns into a step anchor.", atLeast: 0), .ref("step-anchor")],
            )),
            .init("step-anchor", stepAnchor),
            .init("caption-end", captionEnd),
            .init("element", SceneFile.element),
            .init("color", .string("A colour: #RRGGBB, or #RRGGBBAA with its opacity.", pattern: "^#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$").example("#1F6FEB")),
        ]

        let devices = DeviceType.allCases.map(\.rawValue)
        let root = Schema.object(
            "An edit: the video cut from the takes, for each device type it names. Anything in a clip, or at the top, can be given again under a device type, and applies only to that type's video.",
            [
                FileSchema.schemaKey,
                .init("intent", .string("What the video is there to show. Not read by the render.")),
                .init("devices", .array("The device types it makes a video for.", of: .choice(nil, devices), minItems: 1, unique: true)),
                .init("music", .ref("music")),
                .init("tapSound", .ref("tap-sound")),
                .init("takeAudioVolume", .number("The level of the take's own sound, where a clip plays it.", atLeast: 0).defaulting(to: 1)),
                .init("background", .ref("color", "The colour of letterbox bands, and of the corners a turn uncovers.").defaulting(to: "#000000")),
                .init("turns", turns.defaulting(to: "letterboxed")),
                .init("turnBlur", .ref("turn-blur")),
                .init("touchColor", .ref("color", "The colour touches are drawn in: a filled ring, its fill at 45% of the colour's opacity and its rim at 90%.").defaulting(to: "#FFFFFF")),
                .init("clips", .array(nil, of: .ref("clip"), minItems: 1)),
            ],
            required: ["devices", "clips"],
        )

        // Every object can be given again under a device type, as a partial copy laid over it.
        let objects = definitions.filter { $0.schema.type == ["object"] && !$0.schema.properties.isEmpty }.map(\.name)
        let overridable = definitions.map { definition in
            guard objects.contains(definition.name) else { return definition }
            return Schema.Property(definition.name, definition.schema.overridden(by: devices, as: .ref("\(definition.name)-override")))
        }
        return FileSchema(
            kind: "edit", title: "An edit",
            root: root.overridden(by: devices, excluding: notOverridable + ["$schema"]),
            definitions: overridable + definitions.map { .init("\($0.name)-override", $0.schema.partial) },
        )
    }
}
