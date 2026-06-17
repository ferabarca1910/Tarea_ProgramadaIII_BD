from flask import Blueprint, flash, redirect, render_template, request, session, url_for

from routes.auth import admin_required, call_procedure, log_event


admin_bp = Blueprint("admin", __name__)


def listar_empleados(nombre=None, documento=None):
    result_sets, output = call_procedure(
        "sp_WebListarEmpleadosConFiltro",
        [nombre, documento, 1, None, None],
    )
    empleados = result_sets[0] if result_sets else []
    return empleados, output.get("ResultCode")


def obtener_empleado(id_empleado):
    result_sets, output = call_procedure("sp_WebObtenerEmpleado", [id_empleado, None])
    empleados = result_sets[0] if result_sets else []
    empleado = empleados[0] if empleados else None
    return empleado, output.get("ResultCode")


@admin_bp.route("/empleados")
@admin_required
def empleados():
    nombre = request.args.get("nombre") or None
    documento = request.args.get("documento") or None
    empleados_data = []
    result_code = None

    try:
        empleados_data, result_code = listar_empleados(nombre, documento)
        log_event(
            12 if documento else 11,
            {
                "accion": "listar_empleados",
                "nombre": nombre,
                "documento": documento,
                "resultCode": result_code,
                "cantidadResultados": len(empleados_data),
            },
        )
    except Exception as exc:
        flash(str(exc), "error")

    return render_template(
        "admin/empleados.html",
        empleados=empleados_data,
        result_code=result_code,
        nombre=nombre or "",
        documento=documento or "",
    )


@admin_bp.route("/impersonar/<int:id_empleado>", methods=["POST"])
@admin_required
def impersonar_empleado(id_empleado):
    try:
        empleado, result_code = obtener_empleado(id_empleado)
    except Exception as exc:
        flash(str(exc), "error")
        return redirect(url_for("admin.empleados"))

    if result_code != 0 or empleado is None:
        flash(f"No se pudo impersonar el empleado. ResultCode: {result_code}", "error")
        return redirect(url_for("admin.empleados"))

    session["id_empleado_impersonado"] = empleado["IdEmpleado"]
    session["nombre_empleado_impersonado"] = empleado["Nombre"]
    log_event(
        11,
        {
            "accion": "impersonar_empleado",
            "idEmpleado": empleado["IdEmpleado"],
            "nombreEmpleado": empleado["Nombre"],
            "valorDocumento": empleado["ValorDocumentoIdentidad"],
        },
    )
    flash(f"Impersonando a {empleado['Nombre']}.", "info")
    return redirect(url_for("empleado.planilla_semanal"))


@admin_bp.route("/regresar-impersonacion")
@admin_required
def regresar_impersonacion():
    log_event(
        11,
        {
            "accion": "regresar_a_admin",
            "idEmpleado": session.get("id_empleado_impersonado"),
            "nombreEmpleado": session.get("nombre_empleado_impersonado"),
        },
    )
    session.pop("id_empleado_impersonado", None)
    session.pop("nombre_empleado_impersonado", None)
    flash("Regresaste al modo administrador.", "info")
    return redirect(url_for("admin.empleados"))
