# Mealee

Melee, but meals. Photograph your plate, your day's nutrients become a fighter, battle
your friends. HackCMU 2026, Food track. Rules and layout are in `CLAUDE.md`.

## Server

```
cp .env.example .env            # fill in Redis, Atlas, IFM if you have them; all optional
make install                    # uv sync
make seed                       # DEMO league, 3 players, a week of fights
make dev                        # http://localhost:8000, arena at /arena/DEMO
make test
```

`data/usda.sqlite` is built once with `make usda` on a machine that can reach USDA.
Until then the server uses `data/nutrients_fallback.yaml` and says so in the log.
The meal editor searches FoodData Central for foods outside the curated detector list.
Set `USDA_API_KEY` to a data.gov key for regular use; the default `DEMO_KEY` is rate-limited.

## Deploy

`railway.toml` builds `server/Dockerfile`. Set `REDIS_URL`, `MONGODB_URI`, `IFM_API_KEY`
as Railway variables. The health check is `/health`. Copy `data/usda.sqlite` into the
repo before deploying or the image ships with the fallback table.

## iOS

See `ios/README.md`. Offline mode: `API_BASE_URL = mock` in `Config.xcconfig`.

## Spikes

`spikes/SPIKE_RESULTS.md` records what has and has not been verified. Run `make spikes`
with photos in `spikes/photos/`.
