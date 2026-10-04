import sqlite3
from app.core.config import settings
from app.core.security import create_access_token

print("DB:", settings.DATABASE_URL)
print("JWT key prefix:", settings.JWT_SECRET_KEY[:20])

con = sqlite3.connect("hyperlocal_dev.db")
cur = con.cursor()

# 1. Ensure admin roles exist
for name, desc in [
    ("admin", "Super Admin - full platform control"),
    ("admin_support", "Support admin"),
    ("admin_moderator", "Moderation admin"),
    ("admin_analyst", "Analytics admin (read-only)"),
]:
    cur.execute("SELECT id FROM roles WHERE name=?", (name,))
    if cur.fetchone() is None:
        cur.execute("INSERT INTO roles (name, description) VALUES (?, ?)", (name, desc))
        print("Created role:", name)

con.commit()

# 2. Assign SUPER admin role to user Akash (id=1)
cur.execute("SELECT id FROM roles WHERE name='admin'")
admin_role_id = cur.fetchone()[0]
cur.execute("UPDATE users SET role_id=? WHERE id=1", (admin_role_id,))
con.commit()

cur.execute("SELECT id, name, phone_number, role_id, status FROM users WHERE id=1")
print("Admin user:", cur.fetchone())

# 3. Generate access token for user id 1
token, jti = create_access_token(subject="1")
print("TOKEN:")
print(token)

with open("admin_token.txt", "w") as f:
    f.write(token)
print("Saved to admin_token.txt")
con.close()
