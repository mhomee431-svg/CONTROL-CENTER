import asyncio, os

async def main():
    import asyncpg
    from urllib.parse import unquote
    pw = unquote('4ywa_ZWGH_8ux69K0b_TQevN4%216E%25zWY')
    conn = await asyncpg.connect(
        host='hyperlocal-production-db.czuwyk426jbf.ap-south-1.rds.amazonaws.com',
        port=5432, database='hyperlocal', user='hyperlocal',
        password=pw, timeout=15
    )
    print('=== CONNECTED ===')
    cnt = await conn.fetchval("SELECT count(*) FROM information_schema.tables WHERE table_schema='public'")
    print('TABLE_COUNT:', cnt)
    rows = await conn.fetch(
        "SELECT tablename FROM pg_tables WHERE table_schema='public' ORDER BY tablename LIMIT 30"
    )
    tables = [r[0] for r in rows]
    print('TABLES:', ','.join(tables))
    try:
        ver = await conn.fetchval("SELECT version_num FROM alembic_version")
        print('ALEMBIC_VERSION:', ver)
    except Exception as ex:
        print('ALEMBIC_VERSION: not found')
    try:
        cols = await conn.fetch(
            "SELECT column_name FROM information_schema.columns WHERE table_name='shops' AND column_name LIKE 'location%' ORDER BY column_name"
        )
        print('SHOP_LOCATION_COLS:', ','.join([r[0] for r in cols]))
    except Exception as ex:
        print('SHOP_LOCATION_COLS: err', str(ex)[:80])
    try:
        pgis = await conn.fetchval("SELECT PostGIS_Version()")
        print('POSTGIS:', str(pgis)[:80])
    except Exception as ex:
        print('POSTGIS: err', str(ex)[:80])
    try:
        idx = await conn.fetchval(
            "SELECT count(*) FROM pg_indexes WHERE tablename='shops' AND indexdef LIKE '%gist%'"
        )
        print('GIST_INDEXES:', idx)
    except Exception as ex:
        print('GIST: err')
    await conn.close()
    print('=== DONE ===')

asyncio.run(main())