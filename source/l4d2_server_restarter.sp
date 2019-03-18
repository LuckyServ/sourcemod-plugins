#include <sourcemod>

new bool:isFirstMapStart = true;
 
public Plugin myinfo =
{
	name = "L4D2 Server Restarter",
	author = "Luckylock",
	description = "Restarts server automatically. Uses the built-in restart of srcds_run",
	version = "1.7",
	url = "https://github.com/LuckyServ/"
};

public void OnPluginStart()
{
    ServerCommand("sm_cvar sv_hibernate_when_empty 0"); 
}

public void OnPluginEnd()
{
    CrashIfNoHumans(INVALID_HANDLE);
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
    SetCommandFlags("crash", GetCommandFlags("crash")&~FCVAR_CHEAT);
    ServerCommand("crash");
}
