// The built-in skins of clawd-usage-winwidget 1.19.0's `skins/` folder, copied as they are (MIT, see LICENSE).

/// The skins that ship with ClawBar: Classic, then upstream's files in `Get-Skins`' order, by file name.
public enum BuiltInSkin: String, Sendable, CaseIterable {
    case classic
    case astronaut, bow, crown, cyanbeanie, dracula, ears, flowershorts, frankenstein, frost, frycook, headtie, nerd
    case netrunner, parka, party, pompom, redcrab, rockerboy, santa, shades, skeleton, squarepants, tired, tophat
    case ushanka, witch, zombie

    public var skin: Skin { Self.parsed[self]! }

    private static let parsed: [BuiltInSkin: Skin] = Dictionary(uniqueKeysWithValues: allCases.map { s in
        (s, s.file.flatMap { Skin.parse($0, id: s.rawValue) } ?? .classic)
    })

    /// The skin file's text; Classic has none.
    private var file: String? {
        switch self {
        case .classic: nil
        case .astronaut: #"""
            ---
            name: Astronaut
            top: -4
            w: #F1F5F9
            g: #6693C5FD
            h: #E6FFFFFF
            c: #94A3B8
            ---
            ......wwwwwww.....
            ....wwgggggggww...
            ...wghhggggggggw..
            ..wghgggggggggggw.
            ..wh............w.
            ..w.............w.
            ..w.............w.
            ..w.............w.
            ..ccccccccccccccc.
            """#
        case .bow: #"""
            ---
            name: Bow
            top: -3
            b: #EF4444
            k: #B91C1C
            ---
            ..........bb...bb.
            .........bbbb.bbbb
            .........bbbbkbbbb
            .........bbbb.bbbb
            ..........bb...bb.
            """#
        case .crown: #"""
            ---
            name: Crown
            g: #FBBF24
            r: #EF4444
            ---
            .....g...g...g....
            .....gg.ggg.gg....
            .....ggggggggg....
            .....ggrgggrgg....
            """#
        case .cyanbeanie: #"""
            ---
            name: Cyan beanie
            top: -4
            c: #22D3EE
            y: #FACC15
            ---
            ........yy........
            .......yyyy.......
            ....ccccccccccc...
            ...yyyyyyyyyyyyy..
            """#
        case .dracula: #"""
            ---
            name: Dracula crab
            body: #CFC8DC
            eyes: #DC2626
            top: 0
            k: #3F3F46
            c: #4C1D95
            r: #B91C1C
            w: #F8FAFC
            y: #FBBF24
            ---
            ...kkkkkkkkkkkkk..
            ...kk....k....kk..
            .c...............c
            .cr.............rc
            .......w...w......
            ..................
            ...ccwwwwywwwwcc..
            ...ccrwwwwwwwrcc..
            """#
        case .ears: #"""
            ---
            name: Cat ears
            o: #D77757
            p: #F9A8D4
            ---
            ...o...........o..
            ...oo.........oo..
            ...opo.......opo..
            ...oppo.....oppo..
            """#
        case .flowershorts: #"""
            ---
            name: Flower shorts
            body: #F9A8D4
            top: -2
            p: #F9A8D4
            g: #4ADE80
            v: #A855F7
            ---
            ........pp........
            .......pppp.......
            ..................
            ..................
            ..................
            ..................
            ..................
            ..................
            ...gvgggvgggvggg..
            ...vgggvgggvgggv..
            """#
        case .frankenstein: #"""
            ---
            name: Frankenstein crab
            body: #65A30D
            top: -2
            k: #1C1917
            s: #27272A
            g: #A1A1AA
            j: #292524
            w: #E7E5E4
            ---
            ...kkkkkkkkkkkkk..
            ...kkkkkkkkkkkkk..
            ...k.kk.kkk.kk.k..
            .......sssss......
            ..................
            .gg.............gg
            ..................
            ..................
            ...jjjjjwwwjjjjj..
            ...jjjjjjwjjjjjj..
            """#
        case .frost: #"""
            ---
            name: Frost
            body: #93C5FD
            eyes: #0C4A6E
            w: #F8FAFC
            b: #2563EB
            ---
            .........w........
            ......bbbbbbb.....
            ....wwwwwwwwwww...
            """#
        case .frycook: #"""
            ---
            name: Fry cook hat
            top: -4
            w: #F8FAFC
            b: #2563EB
            g: #CBD5E1
            ---
            .....wwwwwwwww....
            .....wwwwbwwww....
            .....wwwbbbwww....
            ....ggggggggggg...
            """#
        case .headtie: #"""
            ---
            name: Head tie
            top: -4
            r: #DC2626
            s: #1E3A8A
            k: #991B1B
            ---
            ................rr
            ...............rsr
            ..............rsr.
            ...rrsrrrsrrrsrkk.
            ................r.
            ................r.
            """#
        case .nerd: #"""
            ---
            name: Nerd
            top: 1
            f: #1F2937
            w: #F8FAFC
            g: #A0FFFFFF
            ---
            ...fffff...fffff..
            ...fg..ffwffg..f..
            ...f...f...f...f..
            ...fffff...fffff..
            """#
        case .netrunner: #"""
            ---
            name: Netrunner
            eyes: #5EF6FF
            top: -1
            k: #1E1B2E
            v: #FF0F172A
            c: #5EF6FF
            ---
            ....kkkckkkckkk...
            ..................
            ..................
            ..kvvvvvvvvvvvvvk.
            ..kvcccvvvvvcccvk.
            """#
        case .parka: #"""
            ---
            name: Orange parka
            body: #F97316
            top: -2
            o: #EA580C
            f: #B7804A
            d: #78350F
            ---
            ....ooooooooooo...
            ..oofffffffffffoo.
            ..of...........fo.
            ..of...........fo.
            ..of...........fo.
            ..of...........fo.
            ...fffffffffffff..
            .......d...d......
            .......d...d......
            """#
        case .party: #"""
            ---
            name: Party
            p: #EC4899
            y: #FDE047
            w: #FFFFFF
            ---
            .........w........
            ........ppp.......
            ........pyp.......
            .......ppppp......
            .......yyyyy......
            ......ppppppp.....
            .....ppyyyyypp....
            """#
        case .pompom: #"""
            ---
            name: Pompom beanie
            top: -4
            b: #2563EB
            r: #DC2626
            ---
            ........rr........
            .......rrrr.......
            ....bbbbbbbbbbb...
            ...rrrrrrrrrrrrr..
            """#
        case .redcrab: #"""
            ---
            name: Red crab
            body: #DC2626
            top: -4
            r: #B91C1C
            w: #F8FAFC
            k: #141416
            ---
            ....wkw.....wkw...
            ....www.....www...
            .....r.......r....
            .....r.......r....
            """#
        case .rockerboy: #"""
            ---
            name: Rockerboy
            top: -2
            k: #1C1917
            g: #D4A017
            s: #3B1F0E
            h: #F59E0B
            c: #E5E7EB
            d: #9CA3AF
            ---
            .....kkkkkkkkkk...
            ...kkkkkkkkkkkkkk.
            ...k..........kkk.
            ...ggggggggggggg..
            ...ghssg...ghssg..
            ....sss.....sss...
            .........k......cc
            ........kkk.....dc
            """#
        case .santa: #"""
            ---
            name: Santa hat
            r: #DC2626
            w: #F8FAFC
            ---
            .............ww...
            ..........rrrww...
            .........rrrr.....
            ........rrrrr.....
            .......rrrrrrr....
            ......rrrrrrrrr...
            ...wwwwwwwwwwwww..
            """#
        case .shades: #"""
            ---
            name: Shades
            top: 1
            s: #111827
            w: #9CA3AF
            ---
            ...sssssssssssss..
            ...swsss...swsss..
            ....sss.....sss...
            """#
        case .skeleton: #"""
            ---
            name: Skeleton crab
            body: #E7E5E4
            eyes: #141416
            top: 0
            k: #1C1917
            ---
            ..................
            ..................
            ......k.....k.....
            ......k..k..k.....
            .....k.k.k.k.k....
            ...kkkkkk.kkkkkk..
            ...k...........k..
            ...kkkkkk.kkkkkk..
            """#
        case .squarepants: #"""
            ---
            name: Square pants
            body: #FDE047
            top: 0
            h: #CA8A04
            w: #F8FAFC
            r: #DC2626
            k: #1F2937
            p: #92400E
            ---
            ..........h.......
            ..................
            ........h.........
            ..........h.......
            ..................
            ...wwwwwrrrwwwww..
            ...kkkkkkrkkkkkk..
            ...ppppppppppppp..
            """#
        case .tired: #"""
            ---
            name: Tired
            body: #BD7F6B
            top: 3
            d: #3F2A36
            p: #7A5156
            ---
            ....p.p.....p.p...
            ....ddd.....ddd...
            """#
        case .tophat: #"""
            ---
            name: Top hat
            k: #4B5563
            r: #DC2626
            ---
            ......kkkkkkk.....
            ......kkkkkkk.....
            ......kkkkkkk.....
            ......rrrrrrr.....
            ...kkkkkkkkkkkkk..
            """#
        case .ushanka: #"""
            ---
            name: Green ushanka
            top: -3
            g: #22C55E
            d: #15803D
            ---
            .....ggggggggg....
            ...ggggggggggggg..
            ..ddddddddddddddd.
            .dd.............dd
            .dd.............dd
            ..d.............d.
            """#
        case .witch: #"""
            ---
            name: Witch hat
            k: #7C3AED
            o: #F97316
            ---
            ..........kk......
            .........kkk......
            ........kkkk......
            .......kkkkkk.....
            .......oooooo.....
            ...kkkkkkkkkkkkk..
            """#
        case .zombie: #"""
            ---
            name: Zombie crab
            body: #8DA67E
            eyes: #450A0A
            top: 0
            d: #5E7A52
            r: #9F1239
            b: #3B5B8C
            ---
            .........dd.......
            ..........d.......
            ..................
            ..................
            .............r....
            ............r.r...
            ...bbbbbbbbbbbbb..
            ...b.bb..bbb.b.b..
            """#
        }
    }
}
