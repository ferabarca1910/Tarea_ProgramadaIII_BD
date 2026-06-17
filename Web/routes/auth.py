from functools import wraps

from flask import Blueprint, current_app, flash, redirect, render_template, request, session, url_for


auth_bp = Blueprint("auth", __name__)


def get_connection():
    try:
        import pyodbc
    except ImportError as exc:
        raise RuntimeError("Falta instalar pyodbc para conectar con SQL Server.") from exc

    return pyodbc.connect(current_app.config["SQL_CONNECTION_STRING"])


def rows_to_dicts(cursor):
    columns = [column[0] for column in cursor.description]
    return [dict(zip(columns, row)) for row in cursor.fetchall()]


def execute_with_result_sets(sql, params=None):
    result_sets = []
    output = {}

    with get_connection() as conn:
        cursor = conn.cursor()
        cursor.execute(sql, params or [])

        while True:
            if cursor.description:
                rows = rows_to_dicts(cursor)
                result_sets.append(rows)
                if rows and any(key.startswith("ResultCode") for key in rows[0].keys()):
                    output.update(rows[0])

            if not cursor.nextset():
                break

    return result_sets, output


def call_login(username, password):
    sql = """
        DECLARE @outIdUsuario INT;
        DECLARE @outTipoUsuario TINYINT;
        DECLARE @outResultCode INT;

        EXEC dbo.sp_Login
            @inUsername = ?
          , @inPassword = ?
          , @outIdUsuario = @outIdUsuario OUTPUT
          , @outTipoUsuario = @outTipoUsuario OUTPUT
          , @outResultCode = @outResultCode OUTPUT;

        SELECT
            @outResultCode AS ResultCode
          , @outIdUsuario AS IdUsuario
          , @outTipoUsuario AS TipoUsuario;
    """
    _, output = execute_with_result_sets(sql, [username, password])
    return output


def obtener_id_empleado(id_usuario):
    sql = """
        SELECT e.IdEmpleado
        FROM dbo.Empleado AS e
        WHERE (e.IdUsuario = ?)
          AND (e.Activo = 1);
    """
    result_sets, _ = execute_with_result_sets(sql, [id_usuario])

    if not result_sets or not result_sets[0]:
        return None

    return result_sets[0][0]["IdEmpleado"]


def login_required(view):
    @wraps(view)
    def wrapped_view(**kwargs):
        if session.get("id_usuario") is None:
            return redirect(url_for("auth.login"))

        return view(**kwargs)

    return wrapped_view


def admin_required(view):
    @wraps(view)
    def wrapped_view(**kwargs):
        if session.get("id_usuario") is None:
            return redirect(url_for("auth.login"))

        if session.get("tipo_usuario") != 1:
            flash("No tiene permisos de administrador.", "error")
            return redirect(url_for("empleado.planilla_semanal"))

        return view(**kwargs)

    return wrapped_view


@auth_bp.route("/", methods=["GET"])
def index():
    if session.get("tipo_usuario") == 1:
        return redirect(url_for("admin.empleados"))

    if session.get("tipo_usuario") == 2:
        return redirect(url_for("empleado.planilla_semanal"))

    return redirect(url_for("auth.login"))


@auth_bp.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        username = request.form.get("username", "").strip()
        password = request.form.get("password", "").strip()

        try:
            result = call_login(username, password)
        except Exception as exc:
            flash(str(exc), "error")
            return render_template("login.html")

        result_code = result.get("ResultCode")

        if result_code == 0:
            session.clear()
            session["id_usuario"] = result.get("IdUsuario")
            session["tipo_usuario"] = result.get("TipoUsuario")
            session["username"] = username

            if session["tipo_usuario"] == 1:
                return redirect(url_for("admin.empleados"))

            session["id_empleado"] = obtener_id_empleado(session["id_usuario"])
            return redirect(url_for("empleado.planilla_semanal"))

        flash(f"Login no exitoso. ResultCode: {result_code}", "error")

    return render_template("login.html")


@auth_bp.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("auth.login"))
