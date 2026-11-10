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
                .init("configuration", .string("The build configuration, which must be development-signed for the device.", nonEmpty: true).defaulting(to: ProjectSettings.SchemeBuild.defaultConfiguration)),
                .init("allowProvisioningUpdates", .bool("Lets xcodebuild register the device and update profiles on your team.").defaulting(to: ProjectSettings.SchemeBuild.defaultAllowProvisioningUpdates)),
                .init("optimize", .bool("Builds with the compiler's optimization on, Swift at -O and C at -Os, whatever the configuration says, so the app runs as fast as its users see it.").defaulting(to: ProjectSettings.SchemeBuild.defaultOptimize)),
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
                .init("output", .string("Where takes and cuts go. \(path)", nonEmpty: true).defaulting(to: Project.defaultOutputDirectoryName)),
                .init("hitchWarning", .number(
                    "The milliseconds the app's main thread must miss frames for, at once, for `record` and `cut` to warn of it.", atLeast: 0,
                ).defaulting(to: ProjectSettings.defaultHitchWarning)),
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
                ).defaulting(to: defaultState)),
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
                ).defaulting(to: defaultPreviewAspect)),
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
                .init("duration", .number("Seconds the drag takes.", above: 0).defaulting(to: Step.defaultDragDuration)),
            ], required: ["from", "to"])),
            .init("type", .object("Types text key by key on the on-screen keyboard.", [
                .init("text", .string("What to type; \\n presses return.", nonEmpty: true)),
                .init("into", .ref("element", "The element to type into; the field already being typed in when not given.")),
            ], required: ["text"])),
            .init("activate", .ref("element", "An accessibility activation of an element, with no touch, for getting somewhere off camera.")),
            .init("orientation", orientation.described("Turns the device, with no hand on it; the step ends when the app has turned and the device has drawn the rotation.")),
            .init("waitFor", Schema.object(
                "Waits until an element is on screen, or with gone until it isn't. The step fails if it doesn't happen in time.",
                elementProperties + [
                    .init("gone", .bool("Waits for the element to leave instead.").defaulting(to: Step.defaultGone)),
                    .init("timeout", .number(
                        "Seconds to wait: at most The Button Heist's longest wait, by default \(Point.number(Step.defaultMaximumWaitTimeout)) s, which \(Step.maximumWaitTimeoutVariable) raises, set where Retake runs and in the set's environment, for the app.",
                        above: 0, atMost: Step.defaultMaximumWaitTimeout,
                    ).defaulting(to: Step.defaultWaitTimeout)),
                ],
            ).atLeastOne(of: ElementTarget.keys)),
            .init("capture", .string(
                "Saves the screen as a still, as it is when the step before has ended and its hold is over, as a PNG named for it in the output directory's captures/<type>/<scene>/, when the scene is recorded. Unique in the scene. Not in setup.",
                pattern: Step.capturePattern,
            )),
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
                .init("leadIn", .number("Seconds recorded before the first step. For a scene that records its launch, they start once the app is reachable, after the launch is recorded.", atLeast: 0).defaulting(to: defaultLeadIn)),
                .init("tail", .number("Seconds recorded after the last step.", atLeast: 0).defaulting(to: defaultTail)),
                .init("defaultHold", .number("The hold of each step that doesn't give its own.", atLeast: 0).defaulting(to: defaultDefaultHold)),
                .init("recordsLaunch", .bool("Starts recording before the app launches, to catch its launch screen.").defaulting(to: defaultRecordsLaunch)),
                .init("orientation", orientation.described("The orientation the device is turned to before the app launches.").defaulting(to: defaultOrientation)),
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
        let volume = Schema.number("Its level, where 1 is as recorded.", atLeast: 0).defaulting(to: Edit.Sound.defaultVolume)
        let turns = Schema.choice(
            "How the video shows the device turning. letterboxed: the app stays upright, landscape letterboxed on the canvas. device: the video stays in the device's frame.",
            Edit.Turns.allCases.map(\.rawValue),
        )
        let region: [Schema.Property] = [
            .init("element", .ref("element", "An element, found in the take's step log at the moment.")),
            .init("part", .ref("part")),
            .init("rect", .ref("rect")),
        ]
        let whole = Edit.Rect.wholeElement
        let from = Schema.ref("anchor", "When it starts; the clip's from when not given.")
        let to = Schema.ref("anchor", "When it ends; the clip's to when not given.")

        let stepReference = Schema.oneOf("A step's id, its number counted from 1, a negative number counting back from the last (-1 is the last), or start or end, the take's own first and last frames. Prefer the id, which survives steps being added to the scene.", [
            .string(nil, nonEmpty: true),
            { var number = Schema.integer(); number.not = [{ var zero = Schema(); zero.choices = [0]; return zero }()]; return number }(),
        ])
        let clip = Schema.object("A stretch of a take, played in order.", [
            .init("id", .string("Names the clip, for a caption to run on into it. Unique in the edit.", nonEmpty: true)),
            .init("intent", .string("What the clip is there to show, for whoever changes the video later. Not read by the render.")),
            .init("take", .string("The scene whose take the clip is cut from.", nonEmpty: true)),
            .init("from", .ref("anchor", "Where the clip starts in the take.")),
            .init("to", .ref("anchor", "Where it ends.")),
            .init("speed", .number("How fast it plays: 2 is twice as fast.", above: 0).defaulting(to: Edit.Clip.defaultSpeed)),
            .init("crossfade", .number("Seconds it cross-fades in over the clip before.", atLeast: 0).defaulting(to: Edit.Clip.defaultCrossfade)),
            .init("audioCrossfade", .number("Seconds the sound cross-fades over, when longer than crossfade, which the picture still cross-fades over: the clip before's take sound fades out over this long before that clip ends, and this clip's starts as it does, this minus crossfade ahead of the picture and from as far before `from` in the take, fading in until the clip before ends. Each side fades so even when the other plays no take sound. The clip's sound starts no earlier than its take, or the clip before, does.", atLeast: 0)),
            .init("touches", .bool("Draws the take's touches, from the step log.").defaulting(to: Edit.Clip.defaultTouches)),
            .init("touchColor", .ref("color", "The color of the clip's touches; the edit's touchColor when not given.")),
            .init("touchColors", .array("Colors for single touches, over the clip's or the edit's.", of: .object(nil, [
                .init("step", stepReference),
                .init("color", .ref("color")),
            ], required: ["step", "color"]))),
            .init("takeAudio", .bool("Plays the take's own sound with the clip.").defaulting(to: Edit.Clip.defaultTakeAudio)),
            .init("captions", .array(nil, of: .ref("caption"))),
            .init("sounds", .array("Sound effects, played at normal speed however fast the clip plays.", of: .ref("sound"))),
            .init("spotlight", .ref("spotlight")),
            .init("blurs", .array("Blurs over a stretch of the take, for anything private it shows.", of: .ref("blur"))),
            .init("stills", .array("Frames of other takes, popped in over the clip.", of: .ref("still"))),
            .init("stillsIn", .ref("anchor", "When the first still pops in, the rest following one after another, 0.22 s apart; 0.35 s into the clip when not given.")),
            .init("stillsOut", .ref("anchor", "When the stills pop out, one after another in the order they popped in; they stay to the clip's end when not given.")),
            .init("stillsBackground", .ref("color", "A color filling the canvas behind the stills, fading in as the first pops in, so they stand on it rather than on the clip's picture.")),
            .init("card", .ref("card")),
            .init("devices", .array("The device types whose videos play it; every one of the edit's when not given.", of: .choice(nil, DeviceType.allCases.map(\.rawValue)), minItems: 1, unique: true)),
            .init("turns", turns.described("How this clip shows the device turning; the edit's turns when not given.")),
            .init("turnBlur", .ref("turn-blur")),
        ], required: ["take", "from", "to"])

        let caption = Schema.object("Text over the video, from its from to its to.", [
            .init("text", .string(nil, nonEmpty: true)),
            .init("y", .number("Its center, as a share of the video's height: 0 at the top, 1 at the bottom.", atLeast: 0, atMost: 1)),
            .init("color", .ref("color")),
            .init("from", .ref("anchor", "When it starts; once its clip has faded in when not given.")),
            .init("to", .oneOf("When it ends: an anchor in its clip's take, or, naming a later clip, in that clip's take; as the next clip starts to fade in when not given.", [
                .ref("anchor"), .ref("caption-end"),
            ])),
            .init("symbol", .ref("symbol")),
        ], required: ["text", "y", "color"])

        var stepAnchor = Schema.object("A step, and where to go from it.", [
            .init("step", stepReference),
            .init("offset", .number("Seconds from the step's start, or its end with edge end: forward when positive, back when negative; 0 is that edge itself.")),
            .init("fraction", .number("A share of the way from the step's start, or its end with edge end, to the neighboring step: forward when positive, to the next step's start, back when negative, to the previous step's end.", atLeast: -1, atMost: 1)),
            .init("edge", .choice("Which of the step's edges the anchor is at, and counts its offset or fraction from: start, the default, or end.", Anchor.Edge.allCases.map(\.rawValue))),
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
            .init("card", .object("A color covering the clip's picture, and everything drawn over it but its captions, for a card between clips: over the whole clip, fading in and out with the cross-fades either side, or from its from to its to.", [
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
                .init("padding", .number("Points of space around it.", atLeast: 0).defaulting(to: Edit.Spotlight.defaultPadding)),
                .init("color", .ref("color", "The ring's color.").defaulting(to: Edit.Spotlight.defaultColor)),
                .init("from", from), .init("to", to),
            ]).exactlyOne(of: ["element", "rect"])),
            .init("blur", Schema.object("A blur over an element or a rectangle.", region + [
                .init("from", from), .init("to", to),
                .init("radius", .number("How strong the blur is: the Gaussian blur's radius, its standard deviation, in screen points, scaled to the canvas as the blur's rectangle is.", above: 0).defaulting(to: Edit.Blur.defaultRadius)),
            ]).exactlyOne(of: ["element", "rect"])),
            .init("still", .object("A frame of another take, popped in over the clip.", [
                .init("take", .string("The scene whose take it's from.", nonEmpty: true)),
                .init("at", .ref("anchor", "The moment in that take.")),
            ], required: ["take", "at"])),
            .init("rect", .object("A rectangle of the screen, each side in screen points or a percentage of the screen as the device faced.", [
                .init("x", .length(nil)), .init("y", .length(nil)),
                .init("width", .length(nil, aboveZero: true)), .init("height", .length(nil, aboveZero: true)),
            ], required: ["x", "y", "width", "height"])),
            .init("part", .object("Part of the element, each side in points from its top-left corner or a percentage of its frame; its whole frame on a side not given, as \"part\": { \"x\": \"62%\", \"width\": \"38%\" } is its right 38%.", [
                .init("x", .length(nil, of: "the element").defaulting(to: whole.x)), .init("y", .length(nil, of: "the element").defaulting(to: whole.y)),
                .init("width", .length(nil, aboveZero: true, of: "the element").defaulting(to: whole.width)),
                .init("height", .length(nil, aboveZero: true, of: "the element").defaulting(to: whole.height)),
            ])),
            .init("music", .object("Plays under the whole video.", [
                .init("file", file), .init("volume", volume),
                .init("fadeOut", .number("Seconds it fades out over at the end.", atLeast: 0).defaulting(to: Edit.Music.defaultFadeOut)),
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
            .init("color", .string("A color: #RRGGBB, or #RRGGBBAA with its opacity.", pattern: "^#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$").example("#1F6FEB")),
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
                .init("takeAudioVolume", .number("The level of the take's own sound, where a clip plays it.", atLeast: 0).defaulting(to: Edit.defaultTakeAudioVolume)),
                .init("background", .ref("color", "The color of letterbox bands, and of the corners a turn uncovers.").defaulting(to: Edit.defaultBackground)),
                .init("turns", turns.defaulting(to: Edit.defaultTurns)),
                .init("turnBlur", .ref("turn-blur")),
                .init("touchColor", .ref("color", "The color touches are drawn in: a filled ring, its fill at 45% of the color's opacity and its rim at 90%.").defaulting(to: Edit.defaultTouchColor)),
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

// MARK: - Step logs

extension TakeLog {
    public static var schema: FileSchema {
        let seconds = "seconds into the movie, to the millisecond"
        var format = Schema.integer(
            "The step log's format. Retake doesn't write it: a log without it is format 1, the only one so far. A log of a later format was recorded by a newer Retake, and this one refuses it, saying to update Retake.",
        )
        format.choices = [.number(Double(Self.format))]
        let size = Schema.tuple("[width, height], in capture pixels.", of: .integer(nil, atLeast: 0), count: 2)
        let aspect = Schema.oneOf(nil, [.ref("shape"), .ref("preview-aspect")])
        let root = Schema.object(
            "A take's step log, `<scene>.json` beside its movie `<scene>.mov` in the output directory's `takes/<type>/`, or `<scene>.previous.json` or `<scene>.failed.json` beside theirs: what was recorded, with what, and when each step happened on the movie's own clock, where it touched, and what was on screen after it. Retake writes it when it records the take, and reads it to list, clean and cut takes; a project doesn't write or edit it. Times are \(seconds); positions and sizes on the screen are its points, portrait, to the hundredth.",
            [
                .init("format", format),
                .init("scene", .string("The scene recorded, as its file in `scenes/<type>/` is named, without `.json`.", nonEmpty: true)),
                .init("take", Schema.integer(nil, atLeast: 1).deprecated("Deprecated: the take's number among the scene's, from 1, which takes recorded when they were numbered give. Still read, and ignored.")),
                .init("set", .string("The set the scene started on.", nonEmpty: true)),
                .init("state", .choice("The set's state, which the take's data started from.", SetFile.State.allCases.map(\.rawValue))),
                .init("deviceType", .choice("The type of device recorded.", DeviceType.allCases.map(\.rawValue))),
                .init("device", .object("The device recorded. Nothing personal: not its name, nor its UDID.", [
                    .init("model", .string("Its hardware identifier, such as iPad13,4.")),
                    .init("marketingName", .string("Its marketing name, such as iPad Pro (11-inch) (3rd generation), when devicectl gives one.")),
                    .init("os", .string("Its iOS version and build, such as 26.6.2 (23G90).")),
                ], required: ["model", "os"])),
                .init("app", .object("The app recorded.", [
                    .init("bundleID", .string("Its bundle ID.", nonEmpty: true)),
                    .init("version", .string("Its CFBundleShortVersionString, as installed on the device.")),
                    .init("build", .string("Its CFBundleVersion.")),
                ], required: ["bundleID"])),
                .init("retake", .string("The version of Retake that recorded it.", nonEmpty: true)),
                .init("buttonHeist", .object("The Button Heist that drove the app: the one embedded in it.", [
                    .init("version", .string("Its version.", nonEmpty: true)),
                    .init("commit", .string("The commit of the local clone it was built from, for one that was.")),
                ], required: ["version"])),
                .init("recordedAt", .string(
                    "When the take was recorded, in ISO 8601: to the second, with any fraction of it, and Z or the zone's offset, such as 2026-11-06T09:30:00Z.",
                    pattern: recordedAtPattern,
                )),
                .init("failure", .string("Why the take failed, for one whose step didn't run; absent for a take that played every step. No edit is cut from a failed take.")),
                .init("duration", .number("The movie's length, in seconds, to the millisecond.", atLeast: 0)),
                .init("size", size.described("The movie's size, [width, height], in capture pixels: its first frame's, which every frame is stored in.")),
                .init("previewAspect", aspect.described("The shape the set's previewAspect gave the app's window: at the top of the screen in portrait, and at its left in landscape; a shape alone is portrait's. Absent when the app filled the screen. The edit crops each frame to it.")),
                .init("aspect", aspect.deprecated("Deprecated: previewAspect's old name, which takes recorded before it was renamed give. Still read, but never with previewAspect.")),
                .init("screen", .tuple(
                    "The device's screen, [width, height], in points, portrait: what the log's touches and frames are in, for the edit to find them in the movie's frames.",
                    of: .number(nil, above: 0), count: 2,
                )),
                .init("frames", .integer("Frames written to the movie.", atLeast: 0)),
                .init("dropped", .integer("Frames the encoder wasn't ready for, which a hitch in the take shows.", atLeast: 0)),
                .init("launch", .object("For a take recorded from before the app launched, as its scene's recordsLaunch asks: when it launched, for an edit to cut in on, each in \(seconds).", [
                    .init("launched", .number("When Retake launched the app.")),
                    .init("reported", .number("When Retake's support library, in the app, reported in.")),
                    .init("connected", .number("When The Button Heist connected to the app.")),
                ], required: ["launched", "reported", "connected"])),
                .init("clock", .object("How the steps were placed on the movie's clock.", [
                    .init("deviceAhead", .number("Seconds the device's clock was ahead of the Mac's, measured once at the start of the take, through which the device's own times for each step are placed. Absent when it couldn't be measured, and every step is timed by the Mac.")),
                ])),
                .init("beforeSteps", .object("What was on screen once the lead-in was over, read just before the first step: what an edit's spotlights and blurs find their elements in until the first step has ended. Absent for a take recorded before Retake read it, or when the screen couldn't be read.", [
                    .init("at", .number("When the screen was read, in \(seconds).")),
                    .init("elements", .array("What was on screen, in the order VoiceOver reads it.", of: .ref("screen-element"))),
                ], required: ["at", "elements"])),
                .init("steps", .array("The steps played while recording, in order. Setup steps, played before recording starts, aren't logged.", of: .ref("step"))),
                .init("shapes", .array("The movie's first shape, and each change after it, as the device turned.", of: .object(nil, [
                    .init("at", .number("When the frames took this shape, in \(seconds).", atLeast: 0)),
                    .init("size", size.described("The frames' size as the device sent them, [width, height], in capture pixels.")),
                    .init("turn", .integer("Degrees clockwise the frames are turned to fit the movie's size: 0, 90, or -90 for a quarter counterclockwise.")),
                ], required: ["at", "size", "turn"]))),
                .init("hitches", .array("Each time the app's main thread missed a frame while it was recorded. Absent when Retake's support library didn't watch.", of: .object(nil, [
                    .init("at", .number("When the app last drew, in \(seconds).")),
                    .init("duration", .number("Seconds until it drew again.", atLeast: 0)),
                ], required: ["at", "duration"]))),
            ],
            required: [
                "scene", "set", "state", "deviceType", "device", "app", "retake", "buttonHeist", "recordedAt", "duration", "size",
                "screen", "frames", "dropped", "clock", "steps", "shapes",
            ],
        )
        var log = root
        log.not = [{ var both = Schema(); both.required = ["previewAspect", "aspect"]; return both }()]

        let point = Schema.tuple("[x, y], in screen points from the top left.", of: .number(), count: 2)
        let step = Schema.object("One step as it was recorded.", [
            .init("number", .integer("Its number among the scene's steps, from 1.", atLeast: 1)),
            .init("id", .string("Its id in the scene, for one that has one.", nonEmpty: true)),
            .init("action", .string("The kind of step: tap, drag, type, activate, orientation, waitFor or capture, or hold for one that's only a pause.", nonEmpty: true)),
            .init("start", .number("When it began, in \(seconds), as the device saw it where it could.")),
            .init("end", .number("When it ended, in \(seconds); for a waitFor, when its element came or went.")),
            .init("timedBy", .choice(
                "Whose times start and end are. device: the device's own, placed through clock.deviceAhead. mac: when the Mac sent the step and heard back, which a round trip either side widens.",
                ["device", "mac"],
            )),
            .init("touch", .ref("point", "Where it touched the screen: a tap's point, by point or on an element, and where a drag came down.")),
            .init("touchEnd", .ref("point", "Where a drag lifted.")),
            .init("touchDuration", .number("Seconds the finger was on the screen, from start, as The Button Heist timed it.", atLeast: 0)),
            .init("elements", .array("What was on screen when it ended, in the order VoiceOver reads it.", of: .ref("screen-element"))),
        ], required: ["number", "action", "start", "end", "timedBy"])
        let element = Schema.object("An element on screen, as VoiceOver knows it, which an edit's spotlights and blurs find.", [
            .init("label", .string("Its accessibility label.")),
            .init("value", .string("Its value.")),
            .init("identifier", .string("The accessibilityIdentifier the app gives it.")),
            .init("hint", .string("Its accessibility hint.")),
            .init("traits", .array("Its traits, by The Button Heist's names.", of: .string())),
            .init("frame", .tuple("Where it is, [x, y, width, height], in screen points.", of: .number(), count: 4)),
            .init("activationPoint", .ref("point", "Where a tap on it touches.")),
        ])
        let shape = Schema.string("A width and a height, each a positive decimal with digits either side of any point, such as 3:4.", pattern: SetFile.Aspect.pattern)
        let shapes = Schema.object("The app window's shape in portrait, and in landscape.", [
            .init("portrait", .ref("shape", "Its shape in portrait, at the top of the screen.")),
            .init("landscape", .ref("shape", "Its shape in landscape, at the left of the screen.")),
        ]).atLeastOne(of: ["portrait", "landscape"])
        return FileSchema(kind: "take", title: "A step log", root: log, definitions: [
            .init("step", step), .init("screen-element", element), .init("point", point), .init("preview-aspect", shapes), .init("shape", shape),
        ])
    }
}
