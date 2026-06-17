import os


class Config:
    SECRET_KEY=os.environ.get("SECRET_KEY", "dev-secret-key")

    #ConexionBD
    SQL_SERVER=os.environ.get("SQL_SERVER", "localhost")
    SQL_DATABASE=os.environ.get("SQL_DATABASE", "PlanillaObrera")
    SQL_USERNAME=os.environ.get("SQL_USERNAME", "sa")
    SQL_PASSWORD=os.environ.get("SQL_PASSWORD", "Mama6678")
    SQL_DRIVER=os.environ.get("SQL_DRIVER", "ODBC Driver 18 for SQL Server")
    SQL_TRUST_CERTIFICATE=os.environ.get("SQL_TRUST_CERTIFICATE", "yes")

    @classmethod
    def connection_string(cls):
        return (
            f"DRIVER={{{cls.SQL_DRIVER}}};"
            f"SERVER={cls.SQL_SERVER};"
            f"DATABASE={cls.SQL_DATABASE};"
            f"UID={cls.SQL_USERNAME};"
            f"PWD={cls.SQL_PASSWORD};"
            f"TrustServerCertificate={cls.SQL_TRUST_CERTIFICATE};"
        )
