#include <sourcemod>

new bool:isFirstMapStart = true;
 
public Plugin myinfo =
{
	name = "L4D2 Server Restarter",
	author = "Luckylock",
	description = "Restarts server automatically. Uses the built-in restart of srcds_run",
	version = "1.8",
	url = "https://github.com/LuckyServ/"
};

public void OnPluginStart()
{
    new ConVar:cvarHibernateWhenEmpty = FindConVar("sv_hibernate_when_empty");
    SetConVarInt(cvarHibernateWhenEmpty, 0, false, false);
    
    RegAdminCmd("sm_rs", KickClientsAndRestartServer, ADMFLAG_ROOT, "Kicks all clients and restarts server");
}

public void OnPluginEnd()
{
    CrashIfNoHumans(INVALID_HANDLE);
}

public Action KickClientsAndRestartServer(int client, int args)
{
    for (new i = 1; i <= MaxClients; ++i) {
        if (IsHuman(i)) {
            KickClient(i, "Restarting"); 
        }
    }

    CrashServer();
}

public void OnMapStart()
{
    if(!isFirstMapStart) {
        CreateTimer(30.0, CrashIfNoHumans, INVALID_HANDLE, TIMER_FLAG_NO_MAPCHANGE); 
    }
    isFirstMapStart = false;
}

public Action CrashIfNoHumans(Handle timer) 
{
    if (!HumanFound()) {
        CrashServer();
    }
}

public bool HumanFound() 
{
    new bool:humanFound = false;
    new i = 1;

    while (!humanFound && i <= MaxClients) {
        humanFound = IsHuman(i);
        ++i;
    }

    return humanFound;
}

public bool IsHuman(client)
{
    return IsClientInGame(client) && !IsFakeClient(client);
}

public void CrashServer()
{
    PrintToServer("L4D2 Server Restarter: Crashing the server...");
    SetCommandFlags("crash", GetCommandFlags("crash")&~FCVAR_CHEAT);
    ServerCommand("crash");
}
