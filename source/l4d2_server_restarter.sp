#include <sourcemod>
 
public Plugin myinfo =
{
	name = "L4D2 Server Restarter",
	author = "Luckylock, Sir",
	description = "Restarts server after every client has disconnected by crashing it. Uses the built-in restart of srcds_run",
	version = "1.3",
	url = "https://github.com/LuckyServ/"
};

public void OnPluginStart()
{
    ServerCommand("sm_cvar sv_hibernate_when_empty 0"); 
}

public void OnClientDisconnect(int client)
{
    if (!IsFakeClient(client)) {

        // Timer to give enough time for a map transition (clients get disconnected)
        CreateTimer(10.0, CrashIfNoHumans);
    }
}

public Action CrashIfNoHumans(Handle timer) 
{
    if (!HumanFound()) {
        CrashServer();
    }

    return Plugin_Continue;
}

public bool HumanFound() 
{
    new bool:humanFound = false;
    new i = 1;

    while (!humanFound && i <= MaxClients) {
        if (IsClientInGame(i)) {
            humanFound = !IsFakeClient(i); 
        }
        ++i;
    }

    return humanFound;
}

public void CrashServer()
{
    PrintToServer("L4D2 Server Restarter: Crashing the server...");
    ServerCommand("sm plugins load_unlock");
    ServerCommand("sm plugins unload smac/smac_cvars.smx");
    ServerCommand("sv_cheats 1");
    ServerCommand("crash");
}
