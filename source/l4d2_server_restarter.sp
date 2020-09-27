#include <sourcemod>

#define MAX_STR_LEN 128

new bool:isFirstMapStart = true;
new bool:isSwitchingMaps = true;
new bool:startedTimer = false;
new Handle:switchMapTimer = INVALID_HANDLE;
 
public Plugin myinfo =
{
	name = "L4D2 Server Restarter",
	author = "Luckylock",
	description = "Restarts server automatically. Uses the built-in restart of srcds_run",
	version = "3",
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
    char kickMessage[MAX_STR_LEN];

    if (GetCmdArgs() >= 1) {
        GetCmdArgString(kickMessage, MAX_STR_LEN);
    } else {
        strcopy(kickMessage, MAX_STR_LEN, "Server is restarting")
    }

    for (new i = 1; i <= MaxClients; ++i) {
        if (IsHuman(i)) {
            KickClient(i, kickMessage); 
        }
    }

    CrashServer();
}

public void OnMapStart()
{
    if(!isFirstMapStart && !startedTimer) {
        CreateTimer(30.0, CrashIfNoHumans, _, TIMER_REPEAT); 
        startedTimer = true;
    }

    if (switchMapTimer != INVALID_HANDLE) {
        KillTimer(switchMapTimer);
    }

    switchMapTimer = CreateTimer(30.0, SwitchedMap);

    isFirstMapStart = false;
}

public void OnMapEnd()
{
    isSwitchingMaps = true;
}

public Action SwitchedMap(Handle timer)
{
    isSwitchingMaps = false;

    switchMapTimer = INVALID_HANDLE;

    return Plugin_Stop;
}

public Action CrashIfNoHumans(Handle timer) 
{
    if (!isSwitchingMaps && !HumanFound()) {
        CrashServer();
    }

    return Plugin_Continue;
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
