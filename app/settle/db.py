from sqlalchemy import create_engine

from settle import config

engine = create_engine(config.DATABASE_URL, pool_size=5, max_overflow=10)
