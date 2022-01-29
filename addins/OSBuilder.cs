using System;
using MCGalaxy.Events;
using MCGalaxy.Events.PlayerEvents;

namespace MCGalaxy {

    public class OsBuilderPlugin : Plugin {
        public override string creator { get { return "Not UnknownShadow200"; } }
        public override string MCGalaxy_Version { get { return "1.9.1.4"; } }
        public override string name { get { return "OsBuilderPlugin"; } }

        public override void Load(bool startup) {
            OnJoiningLevelEvent.Register(DoDemoteAfterLevel, Priority.Low);
            OnJoinedLevelEvent.Register(DoPromotePlayer, Priority.Low);
            OnPlayerConnectEvent.Register(DoDemotePlayer, Priority.Low);
        }

        public override void Unload(bool shutdown) {
            OnJoiningLevelEvent.Unregister(DoDemoteAfterLevel);
            OnJoinedLevelEvent.Unregister(DoPromotePlayer);
            OnPlayerConnectEvent.Unregister(DoDemotePlayer);
        }

        void DoPromotePlayer(Player p, Level prevLevel, Level level, ref bool announce) {
            if (p.Rank != LevelPermission.Guest) return;
            if (!LevelInfo.IsRealmOwner(level, p.name)) {
                if (!level.Config.MOTD.Contains("+builder"))
                    return;
            }

            Group curRank = PlayerInfo.GetGroup(p.name);
            Group newRank = Group.Find(LevelPermission.Builder);

            if (newRank == null) { p.Message("You should have been promoted to Builder but it's missing"); return; }

            ModAction action = new ModAction(p.name, Player.Console, ModActionType.Rank, null);
            // action.targetGroup = curRank;
            action.Metadata = newRank;
            //action.Announce = false;
            OnModActionEvent.Call(action);

        }

        void DoDemoteAfterLevel(Player p, Level lvl, ref bool canJoin) {
            DoDemotePlayer(p);
        }

        void DoDemotePlayer(Player p) {
            if (p.Rank != LevelPermission.Builder) return;

            Group curRank = PlayerInfo.GetGroup(p.name);
            Group newRank = Group.GuestRank;

            ModAction action = new ModAction(p.name, Player.Console, ModActionType.Rank, null);
            // action.targetGroup = curRank;
            action.Metadata = newRank;
            action.Announce = false;
            OnModActionEvent.Call(action);
        }

    }
}
