# Golden Egg — multiplayer MVP

A playable vertical slice of the hunt-and-battle game: find the golden egg for
coins, survive unpredictable battle windows, and lose everything you carry when
you die.

## Running it

1. Download **Godot 4.5** (standard version, not .NET) from <https://godotengine.org/download>.
2. Open Godot, click **Import**, and select `game/project.godot` from this repo.
3. Press **F5** (or the play button) to run.

To play with someone else, one person clicks **Host a game** and the other
enters the host's IP address and clicks **Join a game**. Both machines need
Godot and a copy of the project. Port **8910** (UDP) must be reachable on the
host — on the same home network this works without setup.

To test on your own machine, run the project twice: host in one window, then
join with `127.0.0.1` in the other.

### Dedicated server

```
godot --headless --path game -- --server
```

Players then join using the server's IP. `-- --client` auto-joins 127.0.0.1,
which is handy for quick local testing.

## Controls

| Input | Action |
| --- | --- |
| WASD | Move |
| Shift | Sprint |
| Space | Jump |
| Mouse | Look |
| Left click | Shoot (only during a battle window) |
| Esc | Release / recapture the mouse cursor |

## What's implemented

- **Third-person movement** on a seeded 3D map — terrain, trees, buildings, and
  a ring of barracks used as spawn points.
- **Multiplayer** over ENet, up to 16 players. Roster replication, position
  sync at 20Hz with interpolation for remote players.
- **Golden egg hunt** — the egg spawns at a random spot, and the HUD gives every
  player a direction and distance to it so the hunt is a race rather than a
  random walk. Finding it pays 120 coins and moves the egg elsewhere.
- **Battle windows** — PvP switches on at random intervals (45–90s apart) for a
  random duration (20–60s). Shooting is blocked outside these windows.
- **Loot scatters on death** — coins drop on the ground where you fell and
  anyone nearby can pick them up, including someone who didn't get the kill.
  Nothing is stored anywhere; everything you own is carried.
- **Population-scaled boundary** — the playable ring grows as more players join.
  Step outside it and you take damage until you die.
- **Respawn** at your barracks after 3 seconds, with nothing but your life.

## What's deliberately not built yet

The bounty hunt phase, the hunter role and its powers, weapon tiers and
upgrades, skins, voice chat, persistent accounts, and multi-instance
matchmaking. The point of this slice is to find out whether the core loop —
hunt, fight, lose it all, chase it back — is fun before building on top of it.

## Architecture notes

- The **server owns** the egg position, all damage and deaths, coin balances,
  dropped loot, the phase timer and the boundary. Clients cannot award
  themselves coins or kill anyone by sending a message.
- **Movement is client-reported** for now. That's fine for testing with people
  you know, but it means a modified client could teleport. Server-side movement
  validation is a V1 task, not an MVP one.
- The **map is generated from a fixed seed** on every peer, so terrain never
  needs to be sent over the network.
