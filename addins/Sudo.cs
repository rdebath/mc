
using System;
using System.IO;
using System.Text;
using System.Collections.Generic;
using MCGalaxy.Maths;
using BlockID = System.UInt16;
using MCGalaxy.Commands;
using MCGalaxy.Commands.World;
using MCGalaxy.DB;
using MCGalaxy.Blocks;
using MCGalaxy.Blocks.Extended;
using MCGalaxy.Network;
using MCGalaxy.Util;
using MCGalaxy.Generator;

// TODO: Sudoers text file and editing of that.
// Add extra perm for >=SuperOP to always console.
// Use cases:
// (*) Named users can switch own or others rank on the fly.
// (*) Named users can use "/sudo /ban RichardCranium" even if Guest

namespace MCGalaxy
{
    public class Sudo: Plugin {
        public override string name { get { return "Sudo"; } }
        public override string MCGalaxy_Version { get { return "1.9.3.5"; } }

        public override void Load(bool startup)
        {
            Command.Register(new CmdSudo());
        }

        public override void Unload(bool shutdown)
        {
            Command.Unregister(Command.Find("Sudo"));
        }
    }

    public class CmdSudo : Command2
    {
        // The command's name (what you put after a slash to use this command)
        public override string name { get { return "Sudo"; } }

        // Command's shortcut, can be left blank (e.g. "/copy" has a shortcut of "c")
        public override string shortcut { get { return "su"; } }

        // Which submenu this command displays in under /Help
        public override string type { get { return "other"; } }

        // The default rank required to use this command. Valid values are:
        //   LevelPermission.Guest, LevelPermission.Builder, LevelPermission.AdvBuilder,
        //   LevelPermission.Operator, LevelPermission.Admin, LevelPermission.Nobody
        public override LevelPermission defaultRank { get { return LevelPermission.Admin; } }

        // This is for when a player does /Help
        public override void Help(Player p)
        {
            p.Message("&T/Sudo&S - Run command with Console permission");
        }

        public override void Use(Player p, string message, CommandData data)
        {
            string[] args = message.SplitSpaces(2);
            string cmdName = args[0], cmdArgs = args.Length > 1 ? args[1] : "";
            bool UseCons = false;
            if (cmdName == "su") {
                UseCons = true;
                args = args[1].SplitSpaces(2);
                cmdName = args[0];
                cmdArgs = args.Length > 1 ? args[1] : "";
            }

            if (cmdName == "") { p.Message("No command name given."); return; }

            Command.Search(ref cmdName, ref cmdArgs);

            Command cmd = Command.Find(cmdName);
            if (cmd == null) {
                p.Message("Unknown command \"{0}\".", cmdName); return;
            }

            data.Context = CommandContext.SendCmd;
            data.Rank = LevelPermission.Console;

            // SetRank is actually run by console because of additional errors.
            if (UseCons || cmd.name == "SetRank")
                cmd.Use(Player.Console, cmdArgs, data);
            else
                cmd.Use(p, cmdArgs, data);
        }
    }
}
