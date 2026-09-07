import asyncio, sys

DBHOST = 'hyperlocal-production-db.czuwyk426jbf.ap-south-1.rds.amazonaws.com'
DBPORT = 5432
DBNAME = 'hyperlocal'
DBUSER = 'hyperlocal'
DBPASS = '4ywa_ZWGH_8ux69K0b_TQevN4!6E%zWY'

out = open('_db_final.txt', 'w', encoding='utf-8')

async def main():
    import asyncpg
    conn = await asyncpg.connect(host=DBHOST, port=DBPORT, database=DBNAME,
                                 user=DBUSER, password=DBPASS, timeout=15)
    print('=== CONNECTED ===', file=out)

    cnt = await conn.fetchval("SELECT count(*) FROM information_schema.tables WHERE table_schema='public'")
    print('TABLE_COUNT:', cnt, file=out)

    rows = await conn.fetch(
        "SELECT tablename FROM pg_tables WHERE table_schema='public' AND tablename IN ('shops','users','shop_verifications','alembic_version','product_masters') ORDER BY tablename"
    )
    key_tables = [r[0] for r in rows]
    print('KEY_TABLES:', ','.join(key_tables), file=out)

    try:
        ver = await conn.fetchval("SELECT version_num FROM alembic_version")
        print('ALEMBIC_VERSION:', ver, file=out)
    except Exception as ex:
        print('ALEMBIC_VERSION: not found', str(ex)[:80], file=out)

    try:
        cols = await conn.fetch(
            "SELECT column_name FROM information_schema.columns WHERE table_name='shops' AND column_name LIKE 'location%'"
        )
        loc_cols = [r[0] for r in cols]
        print('SHOP_LOCATION_COLS:', ','.join(loc_cols), file=out)
    except Exception as ex:
        print('SHOP_LOCATION_COLS: error', str(ex)[:80], file=out)

    try:
        pgis = await conn.fetchval("SELECT PostGIS_Version()")
        print('POSTGIS:', str(pgis)[:80], file=out)
    except Exception as ex:
        print('POSTGIS: error', str(ex)[:80], file=out)

    try:
        idx = await conn.fetchval(
            "SELECT count(*) FROM pg_indexes WHERE tablename='shops' AND indexdef LIKE '%gist%'"
        )
        print('GIST_INDEXES_ON_SHOPS:', idx, file=out)
    except Exception as ex:
        print('GIST: error', str(ex)[:80], file=out)

    await conn.close()
    print('=== DONE ===', file=out)

try:
    asyncio.run(main())
except Exception as ex:
    print('FAIL:', str(ex)[:200], file=out)

out.close()
print('done')