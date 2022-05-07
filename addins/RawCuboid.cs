////////////////////////////////////////////////////////////////////////////////
//
// TODO: Compression scheme for multiple PL commands.
//          (Current runs to about 18 bytes per place)
//
// TODO: Portal, map env, set physics.
//
// TODO: Fix extra_permission for SendBatch, SendScript
// TODO: SendScript with extra perm for URL.
//
////////////////////////////////////////////////////////////////////////////////
//
// This command is specifically designed to work from the console.
// It allows a >=SuperOP or realm owner to place or cuboid any number
// of blocks on any level.
//
// In addition fast routines to define level blocks, block props and
// message blocks are included for level definition.
//
// Some commands cannot be run from from the console so a /sendcmd option is
// included to allow a full user to be tasked with other commands.
// (This item is only available to SuperOP+)
//
// This ignores limits on number of blocks, so MUST only be available to
// realm owners and higher.
//
// Also:
//     /SendBatch player [mb style cmd args]
//     /SendScript [player] scriptFileOrURL.mc

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

namespace MCGalaxy
{
    public class Announce: Plugin {
        public override string name { get { return "RawCuboid"; } }
        public override string MCGalaxy_Version { get { return "1.9.3.5"; } }

        public override void Load(bool startup)
        {
            Command.Register(new CmdRawCuboid());
            Command.Register(new CmdSendBatch());
            Command.Register(new CmdSendScript());
        }

        public override void Unload(bool shutdown)
        {
            Command.Unregister(Command.Find("RawCuboid"));
            Command.Unregister(Command.Find("SendBatch"));
            Command.Unregister(Command.Find("SendScript"));
        }
    }

    public class CmdSendBatch : Command2
    {
        public override string name { get { return "SendBatch"; } }
        public override string shortcut { get { return "run"; } }

        public override CommandAlias[] Aliases {
            get { return new [] { new CommandAlias("Sendbat"), }; }
        }

        // Which submenu this command displays in under /Help
        public override string type { get { return "other"; } }

        public override LevelPermission defaultRank { get { return LevelPermission.Guest; } }

        public override void Help(Player p)
        {
            p.Message("/SendBatch /[mb style cmd args]");
            p.Message("SuperOP can send to other players");
            p.Message(" /SendBatch player /[mb style cmd args]");
        }

        public override void Use(Player p, string message, CommandData data)
        {
            Player target;
            if (message[0] != '/')
            {
                string[] parts = message.SplitSpaces(2);

                if (parts.Length != 2) { parts = null; Help(p); return; }

                if (!p.IsSuper && p.Rank < LevelPermission.Admin) {
                    parts = null;
                    p.Message("Only SuperOP may use SendBatch to another player");
                    return;
                }

                target = PlayerInfo.FindMatches(p, parts[0]);
                if (target == null) return;
                message = parts[1];
                parts = null;
            } else {
                target = p;
            }

            List<string> cmds = new List<string>(
                    message
                        .TrimStart('/')
                        .Replace(" |/", "\n").Replace("||/", "|/")
                        .Split('\n', StringSplitOptions.RemoveEmptyEntries)
                );

            // Setup so I can use the delay command.
            CommandData mbdata = target.DefaultCmdData;
            mbdata.Context = CommandContext.MessageBlock;
            target.HandleCommands(cmds, mbdata);
            p.Message("Commands sent to {0}", target.FullName);
            cmds = null;
        }
    }

    public class CmdSendScript : Command2
    {
        public override string name { get { return "SendScript"; } }
        public override string shortcut { get { return "Call"; } }

        public override CommandAlias[] Aliases {
            get { return new [] { new CommandAlias("SendScript"), }; }
        }

        // Which submenu this command displays in under /Help
        public override string type { get { return "other"; } }

        public override LevelPermission defaultRank { get { return LevelPermission.AdvBuilder; } }

        public override void Help(Player p)
        {
            p.Message("/SendScript [player] scriptFileOrURL.mc");
        }

        public override void Use(Player p, string message, CommandData data)
        {
            const string Extension = ".mc";
            Player target;
            CommandData mbdata;

            {
                string[] parts = message.SplitSpaces(2);

                if (parts.Length == 1) {
                    target = p;
                    mbdata = data;
                } else {
                    if (parts.Length != 2) { Help(p); return; }

                    if (!p.IsSuper && p.Rank < LevelPermission.Admin) {
                        p.Message("Only SuperOP may use SendScript to another user.");
                        return;
                    }

                    target = PlayerInfo.FindMatches(p, parts[0]);
                    if (target == null) return;
                    message = parts[1];
                    mbdata = target.DefaultCmdData;
                }
            }

            if (!message.CaselessEnds(Extension))
                message = message + Extension;

            List<string> cmds;

            if (message.IndexOf('/') >= 0) {
                p.Message("Downloading file at URL");
                HttpUtil.FilterURL(ref message);
                byte[] httpdata = HttpUtil.DownloadData(message, p);
                string msg = Encoding.UTF8.GetString(httpdata);
                httpdata = null;
                cmds = new List<string>(
                    msg.Split('\n', StringSplitOptions.RemoveEmptyEntries)
                );
                msg = null;
            } else {
                p.Message("Loading file {0}", message);
                string path = Paths.ImportsDir + message;
                cmds = new List<string>( File.ReadAllLines(path));
            }
            cmds.RemoveAll(string.IsNullOrEmpty);
            cmds.RemoveAll(item => item.StartsWith("#"));

            // Concat. lines that end with ' \' with the next one.
            cmds = new List<string>(string.Join("\007", cmds)
                    .Replace(" \\\007", "")
                    .Split("\007", StringSplitOptions.RemoveEmptyEntries));

            cmds = cmds.ConvertAll(s => s.TrimStart('/'));

            // Setup so I can use the delay command.
            mbdata.Context = CommandContext.MessageBlock;
            target.HandleCommands(cmds, mbdata);
            cmds = null;
            p.Message("Command list started by {0}", target.FullName);
        }
    }

    public class CmdRawCuboid : Command2
    {
        // The command's name (what you put after a slash to use this command)
        public override string name { get { return "RawCuboid"; } }

        // Command's shortcut, can be left blank (e.g. "/copy" has a shortcut of "c")
        public override string shortcut { get { return "rc"; } }

        public override CommandAlias[] Aliases {
            get { return new [] { new CommandAlias("RawPlace") }; }
        }

        // Which submenu this command displays in under /Help
        public override string type { get { return "other"; } }

        // Whether or not this command can be used in a museum. Block/map altering commands should return false to avoid errors.
        public override bool museumUsable { get { return false; } }

        // The default rank required to use this command. Valid values are:
        //   LevelPermission.Guest, LevelPermission.Builder, LevelPermission.AdvBuilder,
        //   LevelPermission.Operator, LevelPermission.Admin, LevelPermission.Nobody
        public override LevelPermission defaultRank { get { return LevelPermission.Builder; } }

        private int counter;
        private int err_count;
        private bool Buffering;
        private bool BlockDBActive;
        private bool Silence;
        private BlockID last_block = Block.Invalid;
        private string last_block_name = "-";
        private bool Save_Blocks;
        private bool Save_Props;
        private bool Save_Settings;
        private const byte LevelScope = (byte)2;

        // This is for when a player does /Help RawCuboid
        public override void Help(Player p)
        {
            p.Message("/RawCuboid - Place blocks, lots of them.");
            p.Message("/rc [level|-] [subcommand]*");
            p.Message("For subcommands use /help rc cmds");
        }

        public override void Help(Player p, string message) {
            p.Message("Subcommands:");
            p.Message(" pl B X Y Z");
            p.Message(" box B X1 Y1 Z1 X2 Y2 Z2");
            p.Message(" msg \"Hello world\"");
            p.Message(" sendcmd player cmd \"args\"");
            p.Message(" mb BlockName X Y Z \"MB Contents\"");
            p.Message(" NoBlockDB, BlockDB, Pause, Quiet, lb, Portal");
        }

        // This is for when a player executes this command by doing /RawCuboid
        //   p is the player object for the player executing the command.
        //   message is the arguments given to the command. (e.g. for '/update this', message is "this")
        public override void Use(Player p, string message, CommandData data)
        {
            Level lvl;
            bool force_reload = false;
            /* This scope is so that everything I control is certain to be released to the GC */
            {
                string[] parts = SliceString(message);
                message = null; // Free up space; probably has other pointers, buuuut.

                if (parts.Length == 0) { Help(p); return; }

                if (parts[0] == "") {
                    lvl = null;
                } else {
                    if (parts[0] == "-") {
                        lvl = p.level;
                    } else {
                        lvl = LevelInfo.FindExact(parts[0]);
                    }
                    if (lvl == null) {
                        p.Message("Level {0} does not exist or it is not loaded",
                            parts[0]);
                        return;
                    }

                    if (!p.IsSuper &&
                        p.Rank < LevelPermission.Admin &&
                        !LevelInfo.IsRealmOwner(lvl, p.name)) {
                            p.Message("You may only perform that action on your own map."); return;
                    }

                    if (!lvl.Config.Deletable || !lvl.Config.Buildable) {
                        p.Message("Modification (Place/Delete) is disabled on this level."); return;
                    }
                }

                int cmdcount = 0;
                bool paused_physics = false;
                Buffering = true;
                BlockDBActive = true;
                counter = 0;
                err_count = 0;
                Save_Blocks = false;
                Save_Props = false;
                Save_Settings = false;

                if (parts.Length > 5000)
                    Buffering = false; // Don't bother even trying

                int argno = 1;
                while(argno < parts.Length) {
                    if (parts[argno].CaselessEq("msg") && argno+1 < parts.Length) {
                        p.Message("msg: {0}", parts[argno+1]);
                        argno+=2;
                    } else if (parts[argno] == "") {
                        argno++;
                    } else if (parts[argno].CaselessEq("sendcmd") && argno+3 < parts.Length) {
                        if (!p.IsSuper && p.Rank < LevelPermission.Admin) {
                            p.Message("Only SuperOP may use SendCmd");
                            break;
                        }
                        if (!DoSendCmd(p, parts, argno+1))
                            break;
                        argno+=4;
                    } else if (parts[argno].CaselessEq("quiet")) {
                        Silence = true;
                        argno++;

                    } else if (lvl == null) {
                        p.Message("Errored function at offset {0} = {1} {2}", argno, parts[argno], parts.Length);
                        break;

                    } else if (parts[argno].CaselessEq("pl") && argno+4 < parts.Length) {
                        if (!DoPlace(p, lvl, parts, argno+1, Buffering))
                            break;
                        argno+=5;
                    } else if (parts[argno].CaselessEq("box") && argno+7 < parts.Length) {
                        if (!DoBox(p, lvl, parts, argno+1, Buffering))
                            break;
                        argno+=8;
                    } else if (parts[argno].CaselessEq("mb") && argno+5 < parts.Length) {
                        if (!p.IsSuper && p.Rank < LevelPermission.Admin) {
                            // Can't be bothered to check the extended permissions. Maybe later.
                            p.Message("Only SuperOP may create a messagebox with this command");
                            break;
                        }
                        if (!DoMessageBox(p, lvl, parts, argno+1, (data.Context == CommandContext.MessageBlock) ))
                            break;
                        argno+=6;
                    } else if (parts[argno].CaselessEq("lb") && argno+2 < parts.Length) {
                        int ArgUsed = DoLevelBlock(p, lvl, parts, argno, Buffering);
                        if (ArgUsed == 0)
                            break;
                        argno+=ArgUsed;
                    } else if (parts[argno].CaselessEq("resize") && argno+3 < parts.Length) {
                        if (!DoResizeCmd(p, ref lvl, parts, argno+1))
                            break;
                        argno+=4;
                    } else if (parts[argno].CaselessEq("texture") && argno+1 < parts.Length) {
                        if (!DoTextureCmd(p, lvl, parts, argno+1, Buffering))
                            break;
                        argno+=2;
                    } else if (parts[argno].CaselessEq("noblockdb")) {
                        BlockDBActive = false;
                        argno++;
                    } else if (parts[argno].CaselessEq("blockdb")) {
                        BlockDBActive = true;
                        argno++;
                    } else if (parts[argno].CaselessEq("reload")) {
                        Buffering = false;
                        force_reload = true;
                        argno++;
                    } else if (parts[argno].CaselessEq("pause")) {
                        // This might make the physics thread stutter for
                        // half a second or more; beware.
                        if (lvl.physics > 0 && lvl.physics != 5) {
                            paused_physics = !lvl.PhysicsPaused;
                            lvl.PhysicsPaused = true;
                        }
                        argno++;
                    } else if (parts[argno].CaselessEq("nophysics")) {
                        lvl.SetPhysics(0);
                        lvl.ClearPhysics();
                        Save_Settings = true;
                        argno++;

                    } else {
                        p.Message("Unknown or short function at offset {0} = {1} {2}", argno, parts[argno], parts.Length);
                        break;
                    }

                    cmdcount++;
                    if (Save_Blocks) Buffering = false;
                }

                if (lvl != null ) {
                    if (paused_physics)
                        lvl.PhysicsPaused = false;

                    if (Save_Settings)
                        lvl.SaveSettings();

                    if (Save_Blocks)
                        BlockDefinition.Save(false, lvl);

                    if (Save_Props) {
                        string path = "_" + lvl.name;
                        byte scopeId = LevelScope;
                        BlockProps.Save(path, lvl.Props, scopeId);
                    }

                    if ((!p.Ignores.DrawOutput && !Silence) || err_count > 0) {
                        if (err_count > 0) {
                            p.Message("Actioned {0} block updates in {1} commands with {2} errors.",
                                counter, cmdcount, err_count);
                            if (err_count>10)
                                p.Message("Only the first ten errors were shown.");
                        } else if (counter == 1 && cmdcount == 1)
                            p.Message("Placed a block.");
                        else if (counter == 1)
                            p.Message("Placed a block while running {0} commands.", cmdcount);
                        else
                            p.Message("Actioned {0} block updates in {1} commands.", counter, cmdcount);
                    }
                }
            }

            if (force_reload || (!Buffering && counter > 0)) {
                LevelActions.ReloadAll(lvl, p, true);
                Server.DoGC();
            }
        }

        static string[] SliceString(string msg)
        {
            char[] parmChars = msg.ToCharArray();
            bool inQuote = false;
            for (int index = 0; index < parmChars.Length; index++)
            {
                if (parmChars[index] == '"')
                    inQuote = !inQuote;
                if (!inQuote && parmChars[index] == ' ')
                    parmChars[index] = '\n';
                if (parmChars[index] == '\r') parmChars[index] = '\n';
            }
            string[] args = (new string(parmChars)).Split('\n', StringSplitOptions.RemoveEmptyEntries);

            for (int index = 0; index < args.Length; index++ )
            {
                if (args[index].StartsWith('"') && args[index].EndsWith('"') && args[index].Length >= 2) {
                    args[index] = args[index]
                        .Substring(1,args[index].Length-2)
                        .Replace("\"\"", "\"");
                }
            }
            return args;
        }

        static BlockID ParseBlock(Level lvl, string input) {
            BlockDefinition[] defs = lvl.CustomBlockDefs;
            BlockID block;
            // raw ID is treated specially, before names
            if (BlockID.TryParse(input, out block)) {
                if (block < Block.CPE_COUNT || (block <= Block.MaxRaw && defs[Block.FromRaw(block)] != null)) {
                    return Block.FromRaw(block);
                }
            }

            byte coreID;
            bool success;

            // Add an '@' to a physics (or CPE) block name to ensure you get it.
            if (input[0] == '@') {
                if (BlockID.TryParse(input.Substring(1), out block)) {
                    if (block <= Block.MaxRaw) {
                        return Block.FromRaw(block);
                    } else if (block <= Block.MaxRaw+256)
                        return (ushort)(block-Block.MaxRaw-1);
                }

                success = Block.Aliases.TryGetValue(input.ToLower().Substring(1), out coreID);
                if (success) return coreID;
            }

            block = GetBlockByName(input, defs);
            if (block != Block.Invalid) return block;

            success = Block.Aliases.TryGetValue(input.ToLower(), out coreID);
            if (success) return coreID;

            // That didn't work; maybe a leading "#" is wrong for Tints.
            if (input.Contains("#")) {
                if (input[0] == '#') {
                    block = GetBlockByName(input.Substring(1), defs);
                    if (block != Block.Invalid) return block;
                }
            } else {
                block = GetBlockByName("#" + input, defs);
                if (block != Block.Invalid) return block;
            }

            return Block.Invalid;
        }

        static BlockID GetBlockByName(string msg, BlockDefinition[] defs) {
            for (int i = 1; i < defs.Length; i++) {
                BlockDefinition def = defs[i];
                if (def == null) continue;
                if (def.Name.Replace(" ", "").CaselessEq(msg)) return def.GetBlock();
            }
            return Block.Invalid;
        }

        private void UpdateBlock(Player p, Level lvl, ushort x, ushort y, ushort z, BlockID block,
                                ushort flags = BlockDBFlags.ManualPlace, bool buffered = true) {
            int index;
            BlockID old = lvl.GetBlock(x, y, z, out index);

            // Say that any replace with Air is a delete.
            bool drawn =
                (flags & BlockDBFlags.ManualPlace) == 0 &&
                block != Block.Air;

            ChangeResult result = lvl.TryChangeBlock(p, x, y, z, block, drawn);
            if (result == ChangeResult.Unchanged) return;

            if (BlockDBActive)
                lvl.BlockDB.Cache.Add(p, x, y, z, flags, old, block);
            if (result == ChangeResult.VisuallySame) return;

            if (buffered && Buffering) {
                lvl.blockqueue.Add(index, block);
            }

            if (Buffering && counter >= 10000) {
                Buffering = false;
                lvl.blockqueue.ClearAll();
                if (!p.Ignores.DrawOutput && !Silence)
                    p.Message("Too many updates, block queue turned off.");
            }
            counter++;
        }

        bool DoPlace(Player p, Level lvl, string[] parts, int pno, bool buffered = true) {
            BlockID block = Block.Air;
            Vec3S32 P = new Vec3S32(lvl.Width-1, lvl.Height-1, lvl.Length-1);

            // Record last block name and number so we can match it quickly again.
            if (parts[pno] == "-" || parts[pno] == last_block_name)
                block = last_block;
            else {
                last_block = block = ParseBlock(lvl, parts[pno]);
                last_block_name = parts[pno];
            }

            if (block == Block.Invalid) {
                if (err_count++ < 10 && !Silence)
                    p.Message("{0} is not a valid block", parts[pno]);
                return true;
            }

            if (!CommandParser.GetCoords(p, parts, pno+1, ref P)) return false;

            // Don't clamp, omit dots outside the map.
            if (P.X < 0 || P.X >= lvl.Width) return true;
            if (P.Y < 0 || P.Y >= lvl.Height) return true;
            if (P.Z < 0 || P.Z >= lvl.Length) return true;

            // P = lvl.ClampPos(P);

            UpdateBlock(p, lvl, (ushort)P.X, (ushort)P.Y, (ushort)P.Z, block, BlockDBFlags.Drawn, buffered);
            return true;
        }

        bool DoBox(Player p, Level lvl, string[] parts, int pno, bool buffered = true) {
            BlockID block = Block.Air;
            Vec3S32 P1 = new Vec3S32(lvl.Width-1, lvl.Height-1, lvl.Length-1);
            Vec3S32 P2 = new Vec3S32(lvl.Width-1, lvl.Height-1, lvl.Length-1);

            // Record last block name and number so we can match it quickly again.
            if (parts[pno] == "-" || parts[pno] == last_block_name)
                block = last_block;
            else {
                last_block = block = ParseBlock(lvl, parts[pno]);
                last_block_name = parts[pno];
            }

            if (block == Block.Invalid) {
                if (err_count++ < 10 && !Silence)
                    p.Message("{0} is not a valid block", parts[pno]);
                return true;
            }

            if (!CommandParser.GetCoords(p, parts, pno+1, ref P1)) return false;
            if (!CommandParser.GetCoords(p, parts, pno+4, ref P2)) return false;

            Vec3S32 p1 = Vec3S32.Min(P1, P2);
            Vec3S32 p2 = Vec3S32.Max(P1, P2);

            // Omit ranges completely outside the level.
            if (p2.X < 0 || p1.X >= lvl.Width) return true;
            if (p2.Y < 0 || p1.Y >= lvl.Height) return true;
            if (p2.Z < 0 || p1.Z >= lvl.Length) return true;

            // Clamp the edges of a cuboid
            p1 = lvl.ClampPos(p1);
            p2 = lvl.ClampPos(p2);

            if (block == Block.Air) {
                // Top to bottom because sand, water and lava fall.
                for (int y = p2.Y; y >= p1.Y; y--)
                    for (int z = p1.Z; z <= p2.Z; z++)
                        for (int x = p1.X; x <= p2.X; x++)
                {
                    UpdateBlock(p, lvl, (ushort)x, (ushort)y, (ushort)z, block, BlockDBFlags.Drawn, buffered);
                }
            } else {
                // Bottom to top because some blocks fall.
                for (int y = p1.Y; y <= p2.Y; y++)
                    for (int z = p1.Z; z <= p2.Z; z++)
                        for (int x = p1.X; x <= p2.X; x++)
                {
                    UpdateBlock(p, lvl, (ushort)x, (ushort)y, (ushort)z, block, BlockDBFlags.Drawn, buffered);
                }
            }

            return true;
        }

        bool DoMessageBox(Player p, Level lvl, string[] parts, int pno, bool InMessageBlock) {

            string Message;
            BlockID block;
            string blockname = parts[pno].ToLower();

            if (blockname == "white") block = Block.MB_White;
            else if (blockname == "black") block = Block.MB_Black;
            else if (blockname == "air")   block = Block.MB_Air;
            else if (blockname == "water") block = Block.MB_Water;
            else if (blockname == "lava")  block = Block.MB_Lava;
            else block = ParseBlock(lvl, blockname);

            if (block == Block.Invalid) {
                if (err_count++ < 10 && !Silence)
                    p.Message("{0} is not a message block", parts[pno]);
                return false;
            }
            if (!lvl.Props[block].IsMessageBlock) {
                if (err_count++ < 10 && !Silence)
                    p.Message("{0} is not a messageblock", parts[pno]);
                return false;
            }
            if (!CommandParser.IsBlockAllowed(p, "place a message block of", block)) {
                if (err_count++ < 10 && !Silence)
                    p.Message("{0} is not an allowed block.", parts[pno]);
                return true;
            }

            if (InMessageBlock)
                Message = parts[pno+4].Replace("||/", "|/");
            else
                Message = parts[pno+4];

            Vec3S32 P = new Vec3S32(lvl.Width-1, lvl.Height-1, lvl.Length-1);

            if (!CommandParser.GetCoords(p, parts, pno+1, ref P)) {
                p.Message("Failed to get cordinates.");
                return false;
            }
            P = lvl.ClampPos(P);

            ushort x = (ushort)P.X;
            ushort y = (ushort)P.Y;
            ushort z = (ushort)P.Z;

            BlockID old = lvl.GetBlock(x, y, z);
            if (!lvl.CheckAffect(p, x, y, z, old, block)) {
                if (err_count++ < 10 && !Silence)
                    p.Message("Failed to create a message block.");
                return true;
            }
            lvl.UpdateBlock(p, x, y, z, block);

            string map = lvl.name;
            object locker = ThreadSafeCache.DBCache.GetLocker(map);

            lock (locker) {
                MessageBlock.Set(map, x, y, z, Message);
            }

            counter++;
            if (!p.Ignores.DrawOutput && !Silence)
                p.Message("Message block created.");
            return true;
        }

        bool DoSendCmd(Player p, string[] parts, int pno) {
            Player target = PlayerInfo.FindMatches(p, parts[pno]);
            if (target == null) return true;

            string cmdName = parts[pno+1], cmdArgs = parts[pno+2];
            Command.Search(ref cmdName, ref cmdArgs);

            Command cmd = Command.Find(cmdName);
            if (cmd == null) {
                if (err_count++ < 10 && !Silence)
                    p.Message("Unknown command to send \"" + cmdName + "\".");
                return true;
            }

            CommandData data = p.DefaultCmdData;
            data.Context = CommandContext.SendCmd;
            data.Rank = p.Rank;
            cmd.Use(target, cmdArgs, data);
            return true;
        }

        bool DoResizeCmd(Player p, ref Level lvl, string[] parts, int pno) {
            
            ushort x = 0, y = 0, z = 0;
            if (!MapGen.GetDimensions(p, parts, pno, ref x, ref y, ref z)) return false;

            // Nothing to do
            if (x == lvl.Width && y == lvl.Height && z == lvl.Length) return true;

            LevelActions.Resize(ref lvl, x, y, z);

            return true;
        }

        bool DoTextureCmd(Player p, Level lvl, string[] parts, int pno, bool buffered = true) {
            if (parts[pno] == "" || parts[pno] == "reset") {
                if (lvl.Config.Terrain == "" && lvl.Config.TexturePack == "") return true;
                lvl.Config.Terrain = "";
                lvl.Config.TexturePack = "";
            } else {
                string url = parts[pno];
                HttpUtil.FilterURL(ref url);

                if (!(url.EndsWith(".png") || url.EndsWith(".zip"))) {
                    p.Message("URL {0} must end in .png (for terrain) or .zip (for texture pack)", url);
                    return true;
                }
                if (url.Length > NetUtils.StringSize) {
                    p.Message("The URL must be " + NetUtils.StringSize + " characters or less.");
                    return true;
                }

                if (url.CaselessEnds(".png")) {
                    lvl.Config.Terrain = url;
                    lvl.Config.TexturePack = "";
                } else {
                    lvl.Config.Terrain = "";
                    lvl.Config.TexturePack = url;
                }
            }
            UpdateAllPlayersTexture(lvl);
            Save_Settings = true;
            return true;
        }

        static void UpdateAllPlayersTexture(Level lvl) {
            Player[] players = PlayerInfo.Online.Items;
            foreach (Player pl in players) {
                if (pl.level != lvl) continue;
                pl.SendCurrentTextures();
            }
            lvl.SaveSettings();
        }


/*
    lb copy 0 %d
    lb remove %d
    lb edit %d pname arg
    blockprops %d reset
    blockprops %d pname arg

    lb remove 66
        --> Removes custom level block and properties.

    lb define 66 20 "#Block Name" alltex=92,draw=3,portal=1,fogcolor=#ffb10a,lavakills,max=16,16,16,collide=0

        --> Copies base block and resets blockprops, then sets individual
            properties etc. Probably best to (nearly) always copy air.
 */

        int DoLevelBlock(Player p, Level lvl, string[] parts, int pno, bool buffered = true) {
            if (parts[pno+1].CaselessEq("remove")) {
                // Removing and existing block definition.
                return DoLevelBlockRemove(p, lvl, parts, pno, buffered);
            } else
            if (parts[pno+1].CaselessEq("define")) {
                return DoLevelBlockDefine(p, lvl, parts, pno, buffered);
            } else
            {
                p.Message("lb subcommand '{0}' at offset {1} is unknown", parts[pno+1], pno+1);
                return 0;
            }
        }

        int DoLevelBlockRemove(Player p, Level lvl, string[] parts, int pno, bool buffered = true) {
            // Removing and existing block definition.
            BlockID block;
            const int args = 2;

            if (pno+args >= parts.Length)
                return 0;

            if (!BlockID.TryParse(parts[pno+2], out block) || block == 0 || block > Block.MaxRaw) {
                if (err_count++ < 10 && !Silence)
                    p.Message("Arg '{0}' at offset {1} is not an editable block number", parts[pno+2], pno+2);
                return args+1;
            }

            block = Block.FromRaw((BlockID)block);

            BlockDefinition dstDef = lvl.CustomBlockDefs[block];
            if (dstDef != null) {

                // If there's a global we just overwrite our level copy.
                BlockDefinition globalDef = BlockDefinition.GlobalDefs[block];
                if (globalDef != null) {
                    // Also sends to client.
                    BlockDefinition.Add(globalDef, lvl.CustomBlockDefs, lvl);
                } else {

                    // Remove existing
                    // Note: This sends to players.
                    BlockDefinition.Remove(dstDef, lvl.CustomBlockDefs, lvl);

                    // This does the server side changes, but the clients become inconsistent.
                    // lvl.CustomBlockDefs[block] = null;
                    // lvl.UpdateCustomBlock(block, null);
                }
                Save_Blocks = true;

                // If the block props are level based, remove them.
                if ((lvl.Props[block].ChangedScope&LevelScope) == LevelScope) {
                    lvl.Props[block] = DefaultProps(lvl, block);
                    lvl.UpdateBlockHandlers(block);
                    Save_Props = true;
                }

            } /* else if it's not actually defined, don't complain! */
            return args+1;
        }

/*
    lb define 66 20 "#Block Name" alltex=92,draw=3,portal=1,fogcolor=#ffb10a,lavakills,max=16,16,16,collide=0
        --> Copies base block and resets blockprops, then sets individual
            properties etc.
*/

        int DoLevelBlockDefine(Player p, Level lvl, string[] parts, int pno, bool buffered = true) {
            const int args = 5;
            if (pno+args >= parts.Length)
                return 0;

            char[] equals_chararray = new char[] {'='}; // Sigh
            BlockID block, srcblk;
            string BlockName = parts[pno+4];
            string[] opts = parts[pno+5].Split(',', StringSplitOptions.RemoveEmptyEntries);

            if (!BlockID.TryParse(parts[pno+2], out block) || block == 0 || block > Block.MaxRaw) {
                if (err_count++ < 10 && !Silence)
                    p.Message("Arg '{0}' at offset {1} is not an editable block number", parts[pno+2], pno+2);
                return args+1;
            }

            if (!BlockID.TryParse(parts[pno+3], out srcblk) || block > Block.MaxRaw) {
                if (err_count++ < 10 && !Silence)
                    p.Message("Arg '{0}' at offset {1} is not a block number", parts[pno+3], pno+3);
                return args+1;
            }

            srcblk = Block.FromRaw((BlockID)srcblk);
            block = Block.FromRaw((BlockID)block);

            // Ideal ...
            //   Do copy from CPE
            //   Do copy from Level block ? Concrete -> Coloured version?
            //   Do NOT copy from Global block -- we are scripting block creation

            BlockDefinition srcDef;
            if (lvl.CustomBlockDefs[srcblk] == null && srcblk < Block.CPE_COUNT)
                srcDef = DefaultSet.MakeCustomBlock(srcblk);
            else if (lvl.CustomBlockDefs[srcblk] == null)
                srcDef = DefaultSet.MakeCustomBlock(0);
            else
                srcDef = lvl.CustomBlockDefs[srcblk];

            BlockDefinition dstDef = lvl.CustomBlockDefs[block];

            dstDef = srcDef.Copy();
            dstDef.SetBlock(block);
            dstDef.InventoryOrder = -1; // We're defining, not copying.
            if (BlockName.Length > 0)
                dstDef.Name = BlockName;

            // Remove any block props.
            bool BlockPropsNeedsUpdate = false;
            if (lvl.Props[block].ChangedScope != (byte)0) {
                lvl.Props[block] = DefaultProps(lvl, block);
                BlockPropsNeedsUpdate = true;
            }

            // Edit dstDef, lvl.Props[block], using  opts
            for(int ar=0; ar<opts.Length; ar++)
            {
                string[] opt = opts[ar].Split(equals_chararray,2);
                if (opt.Length != 2) opt = new string[2]{opt[0], "1"};
                opt[0] = MapPropertyName(opt[0].ToLower());
                if (opt[0] == "min" || opt[0] == "max") {
                    if (ar+2>=opts.Length)
                        break;
                    opt = new string[4]{opt[0], opt[1], opts[ar+1], opts[ar+2]};
                    ar += 2;
                }
                EditProperty(p, lvl, dstDef, lvl.Props, block, opt);
            }

            BlockDefinition.Add(dstDef, lvl.CustomBlockDefs, lvl);
            Save_Blocks = true;

            if (BlockPropsNeedsUpdate || lvl.Props[block].ChangedScope != (byte)0) {
                lvl.UpdateBlockHandlers(block);
                Save_Props = true;
            }

            return args+1;
        }

        bool EditProperty(Player p, Level lvl, BlockDefinition def, BlockProps[] Props, BlockID block, string[] opt) {

            string arg = opt[0];
            string value = opt[1];
            // Both client and server side block properties here.
            switch (arg) {

                case "name":
                    def.Name = value; break;
                case "collide":
                    if (!EditByte(p, value, "Collide type", ref def.CollideType, arg)) return false;
                    break;
                case "speed":
                    {
                        float target = def.Speed;
                        if (!Single.TryParse(value, out target) || target<0.25f || target>3.96f) {
                            if (err_count++ < 10 && !Silence)
                                p.Message("Arg '{0}' is not valid for a {1}", value, "Movement speed");
                        } else
                            def.Speed = target;
                    }
                    break;
                case "toptex":
                    if (!EditUShort(p, value, "Top texture", ref def.TopTex, arg)) return false;
                    break;
                case "alltex":
                    if (!EditUShort(p, value, "All textures", ref def.RightTex, arg)) return false;
                    def.SetAllTex(def.RightTex);
                    break;
                case "sidetex":
                    if (!EditUShort(p, value, "Side texture", ref def.RightTex, arg)) return false;
                    def.SetSideTex(def.RightTex);
                    break;
                case "lefttex":
                    if (!EditUShort(p, value, "Left texture", ref def.LeftTex, arg)) return false;
                    break;
                case "righttex":
                    if (!EditUShort(p, value, "Right texture", ref def.RightTex, arg)) return false;
                    break;
                case "fronttex":
                    if (!EditUShort(p, value, "Front texture", ref def.FrontTex, arg)) return false;
                    break;
                case "backtex":
                    if (!EditUShort(p, value, "Back texture", ref def.BackTex, arg)) return false;
                    break;
                case "bottomtex":
                    if (!EditUShort(p, value, "Bottom texture", ref def.BottomTex, arg)) return false;
                    break;
                case "blockslight":
                    if (!EditBool(p, value, "Blocks light", ref def.BlocksLight, arg)) return false;
                    break;
                case "sound":
                    if (!EditByte(p, value, "Walk sound", ref def.WalkSound, arg)) return false;
                    break;
                case "fullbright":
                    if (!EditBool(p, value, "Full bright", ref def.FullBright, arg)) return false;
                    break;
                case "shape":
                    {
                        bool temp = (def.Shape == 0);
                        if (!EditBool(p, value, "Shape", ref temp, arg)) return false;
                        def.Shape = temp ? (byte)0 : def.MaxZ;
                    }
                    break;
                case "blockdraw":
                    if (!EditByte(p, value, "Block draw", ref def.BlockDraw, arg)) return false;
                    break;
                case "min":
                    // NB: Blockdefs uses the normal Z as vertical convention.
                    if (!EditSByte(p, opt[1], "Min X value", ref def.MinX, arg)) return false;
                    if (!EditSByte(p, opt[2], "Min Y value", ref def.MinZ, arg)) return false;
                    if (!EditSByte(p, opt[3], "Min Z value", ref def.MinY, arg)) return false;
                    break;
                case "max":
                    // NB: Blockdefs uses the normal Z as vertical convention.
                    if (!EditSByte(p, opt[1], "Max X value", ref def.MaxX, arg)) return false;
                    if (!EditSByte(p, opt[2], "Max Y value", ref def.MaxZ, arg)) return false;
                    if (!EditSByte(p, opt[3], "Max Z value", ref def.MaxY, arg)) return false;
                    break;
                case "fogdensity":
                    if (!EditByte(p, value, "Fog density", ref def.FogDensity, arg)) return false;
                    break;
                case "fogcolor":
                    {
                        ColorDesc rgb = default(ColorDesc);
                        if (!Colors.TryParseHex(value, out rgb)) {
                            if (err_count++ < 10 && !Silence)
                                p.Message("&W\"#{0}\" is not a valid HEX color.", value);
                            return false;
                        }
                        def.FogR = rgb.R; def.FogG = rgb.G; def.FogB = rgb.B;
                        return true;
                    }
                case "fallback":
                    BlockID fallback = ParseBlock(lvl, value);

                    if (fallback == Block.Invalid) {
                        if (err_count++ < 10 && !Silence)
                            p.Message("Arg '{0}' is not valid for a {1}", value, "Fallback");
                        return false;
                    }
                    def.FallBack = (byte)fallback;
                    break;

                case "order":
                    int order = 0;
                    if (!Int32.TryParse(value, out order) || order <0 || order>Block.MaxRaw) {
                        if (err_count++ < 10 && !Silence)
                            p.Message("Arg '{0}' is not valid for a {1}", value, "Inventory order");
                        return false;
                    }

                    // Don't let multiple blocks be assigned to same order
                    if (order != def.RawID && order != 0) {
                        for (int i = 0; i < lvl.CustomBlockDefs.Length; i++) {
                            if (lvl.CustomBlockDefs[i] == null || lvl.CustomBlockDefs[i].InventoryOrder != order)
                                continue;
                            if (err_count++ < 10 && !Silence)
                                p.Message("Block {0} already has order {1}", lvl.CustomBlockDefs[i].Name, order);
                            return false;
                        }
                    }

                    def.InventoryOrder = order == def.RawID ? -1 : order;
                    return true;

                    // These are exclusive
                case "portal":
                    {
                        bool temp = false;
                        if (!EditBool(p, value, "portal", ref temp, arg)) return false;
                        if (temp && HasBehaviour(Props, block)) {
                            if (err_count++ < 10 && !Silence)
                                p.Message("Block {0} already has a behaviour", def.Name);
                            return false;
                        }
                        Props[block].IsPortal = temp;
                        Props[block].ChangedScope = LevelScope;
                    }
                    break;
                case "messageblock":
                    {
                        bool temp = false;
                        if (!EditBool(p, value, "messageblock", ref temp, arg)) return false;
                        if (temp && HasBehaviour(Props, block)) {
                            if (err_count++ < 10 && !Silence)
                                p.Message("Block {0} already has a behaviour", def.Name);
                            return false;
                        }
                        Props[block].IsMessageBlock = temp;
                        Props[block].ChangedScope = LevelScope;
                    }
                    break;
                case "door":
                    {
                        bool temp = false;
                        if (!EditBool(p, value, "door", ref temp, arg)) return false;
                        if (temp && HasBehaviour(Props, block)) {
                            if (err_count++ < 10 && !Silence)
                                p.Message("Block {0} already has a behaviour", def.Name);
                            return false;
                        }
                        Props[block].IsDoor = temp;
                        Props[block].ChangedScope = LevelScope;
                    }
                    break;
                case "tdoor":
                    {
                        bool temp = false;
                        if (!EditBool(p, value, "tdoor", ref temp, arg)) return false;
                        if (temp && HasBehaviour(Props, block)) {
                            if (err_count++ < 10 && !Silence)
                                p.Message("Block {0} already has a behaviour", def.Name);
                            return false;
                        }
                        Props[block].IsTDoor = temp;
                        Props[block].ChangedScope = LevelScope;
                    }
                    break;
                case "odoor":
                    if (HasBehaviour(Props, block)) {
                        if (err_count++ < 10 && !Silence)
                            p.Message("Block {0} already has a behaviour", def.Name);
                        return false;
                    }
                    break;

                case "rails":
                    if (!EditBool(p, value, "rails", ref Props[block].IsRails, arg)) return false;
                    Props[block].ChangedScope = LevelScope;
                    break;
                case "waterkills":
                    if (!EditBool(p, value, "waterkills", ref Props[block].WaterKills, arg)) return false;
                    Props[block].ChangedScope = LevelScope;
                    break;
                case "lavakills":
                    if (!EditBool(p, value, "lavakills", ref Props[block].LavaKills, arg)) return false;
                    Props[block].ChangedScope = LevelScope;
                    break;
                case "killer":
                    if (!EditBool(p, value, "killer", ref Props[block].KillerBlock, arg)) return false;
                    Props[block].ChangedScope = LevelScope;
                    break;
                case "opblock":
                    if (!EditBool(p, value, "opblock", ref Props[block].OPBlock, arg)) return false;
                    Props[block].ChangedScope = LevelScope;
                    break;
                case "drownable":
                    if (!EditBool(p, value, "drownable", ref Props[block].Drownable, arg)) return false;
                    Props[block].ChangedScope = LevelScope;
                    break;

                    // Block numbers
                case "stackblock":
                    {
                        BlockID tmpblock = ParseBlock(lvl, value);
                        if (tmpblock == Block.Invalid) {
                            if (err_count++ < 10 && !Silence)
                                p.Message("Arg '{0}' is not valid for a {1}", value, "Stack block");
                            return false;
                        }
                        Props[block].StackBlock = tmpblock;
                        Props[block].ChangedScope = LevelScope;
                    }
                    break;
                case "grass":
                    {
                        BlockID tmpblock = ParseBlock(lvl, value);
                        if (tmpblock == Block.Invalid) {
                            if (err_count++ < 10 && !Silence)
                                p.Message("Arg '{0}' is not valid for a {1}", value, "Grass block");
                            return false;
                        }
                        Props[block].GrassBlock = tmpblock;
                        Props[block].ChangedScope = LevelScope;
                    }
                    break;
                case "dirt":
                    {
                        BlockID tmpblock = ParseBlock(lvl, value);
                        if (tmpblock == Block.Invalid) {
                            if (err_count++ < 10 && !Silence)
                                p.Message("Arg '{0}' is not valid for a {1}", value, "Dirt block");
                            return false;
                        }
                        Props[block].DirtBlock = tmpblock;
                        Props[block].ChangedScope = LevelScope;
                    }
                    break;

                case "deathmessage":
                    Props[block].DeathMessage = value;
                    Props[block].ChangedScope = LevelScope;
                    break;
#if false
                case "animalai":
                    // Really, Animal AI on a *block*, use a bot.
                    break;
#endif

                default:
                    if (err_count++ < 10 && !Silence)
                        p.Message("Unrecognised property: " + arg);
                    return false;
            }

            return true;
        }

        static bool HasBehaviour(BlockProps[] Props, BlockID block) {
            if (Props[block].IsMessageBlock)              return true;
            if (Props[block].IsPortal)                    return true;
            if (Props[block].IsTDoor)                     return true;
            if (Props[block].oDoorBlock != Block.Invalid) return true;
            if (Props[block].IsDoor)                      return true;
            return false;
        }

        bool EditByte(Player p, string value, string propName, ref byte target, string help) {
            if (!Byte.TryParse(value, out target)) {
                if (err_count++ < 10 && !Silence)
                    p.Message("Arg '{0}' is not valid for a {1}", value, propName);
                return false;
            }
            return true;
        }

        bool EditSByte(Player p, string value, string propName, ref byte target, string help) {
            // BEWARE the argument is a Byte type not an SByte.
            int temp = 0;
            if (!Int32.TryParse(value, out temp) || temp< -128 || temp>127) {
                if (err_count++ < 10 && !Silence)
                    p.Message("Arg '{0}' is not valid for a {1}", value, propName);
                return false;
            }
            target = (byte)temp;
            return true;
        }

        bool EditUShort(Player p, string value, string propName, ref ushort target, string help) {
            if (!UInt16.TryParse(value, out target)) {
                if (err_count++ < 10 && !Silence)
                    p.Message("Arg '{0}' is not valid for a {1}", value, propName);
                return false;
            }
            return true;
        }

        bool EditBool(Player p, string input, string propName, ref bool target, string help) {
            if (input.CaselessEq("1") || input.CaselessEq("true")
                || input.CaselessEq("yes") || input.CaselessEq("on")) {
                target = true; return true;
            }

            if (input.CaselessEq("0") || input.CaselessEq("false")
                || input.CaselessEq("no") || input.CaselessEq("off")) {
                target = false; return true;
            }

            if (err_count++ < 10 && !Silence)
                p.Message("Arg '{0}' is not valid for a {1}", input, propName);
            return false;
        }

        static BlockProps DefaultProps(Level lvl, BlockID block) {
            return UnchangedProps(lvl, block) ? Block.Props[block] : BlockProps.MakeEmpty();
        }

        static bool UnchangedProps(Level lvl, BlockID b) {
            return Block.IsPhysicsType(b) || lvl.CustomBlockDefs[b] == BlockDefinition.GlobalDefs[b];
        }

        static string MapPropertyName(string prop) {
            if (prop == "side" || prop == "all" || prop == "top" || prop == "bottom"
                || prop == "left" || prop == "right" || prop == "front" || prop == "back") return prop + "tex";

            if (prop == "sides" || prop == "sidestex") return "sidetex";
            if (prop == "light") return "blockslight";
            if (prop == "bright") return "fullbright";
            if (prop == "walksound") return "sound";
            if (prop == "draw") return "blockdraw";
            if (prop == "mincoords") return "min";
            if (prop == "maxcoords") return "max";
            if (prop == "density") return "fogdensity";
            if (prop == "col" || prop == "fogcol")  return "fogcolor";
            if (prop == "fogcolour") return "fogcolor";
            if (prop == "fallbackid" || prop == "fallbackblock") return "fallback";

            // Physics properties.
            if (prop == "mb")       return "messageblock";
            if (prop == "death")    return "killer";
            if (prop == "deathmsg") return "deathmessage";
            if (prop == "animal")   return "animalai";
            if (prop == "stackid")  return "stackblock";
            if (prop == "drown")    return "drownable";

            return prop;
        }
    }
}


#if false
//reference System.dll
//reference System.Core.dll

// This is slow with huge strings.
using System.Text.RegularExpressions;
using System.Linq;

        static string[] SliceStringRE(string message)
        {
            string[] parts;
            if (message.IndexOf('"') != -1) {
                // Sloooow
                var re = @"\G(""((""""|[^""])+)""|(\S+)) *";
                parts = new Regex(re)
                        .Matches(message)
                        .Cast<Match>()
                        .Select(m => Regex.Replace(
                             m.Groups[2].Success
                                 ? m.Groups[2].Value
                                 : m.Groups[4].Value, @"""""", @""""))
                                 .ToArray();
            } else
                parts = message.Split((char[]) null, StringSplitOptions.RemoveEmptyEntries);
            return parts;
        }
#endif
