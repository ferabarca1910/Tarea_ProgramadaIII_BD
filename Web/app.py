from flask import Flask

from config import Config
from routes.admin import admin_bp
from routes.auth import auth_bp
from routes.empleado import empleado_bp


def create_app():
    app = Flask(__name__)
    app.config.from_object(Config)
    app.config["SQL_CONNECTION_STRING"] = Config.connection_string()

    app.register_blueprint(auth_bp)
    app.register_blueprint(admin_bp, url_prefix="/admin")
    app.register_blueprint(empleado_bp, url_prefix="/empleado")

    return app


app = create_app()


if __name__ == "__main__":
    app.run(debug=True)
