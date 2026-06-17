from flask import Blueprint, flash, redirect, render_template, request, session, url_for

from routes.auth import call_procedure, log_event, login_required


empleado_bp = Blueprint("empleado", __name__)


def obtener_id_empleado_actual():
    if session.get("tipo_usuario") == 1:
        return session.get("id_empleado_impersonado")

    return session.get("id_empleado")


def obtener_id_empleado(id_usuario):
    result_sets, _ = call_procedure("sp_WebObtenerEmpleadoPorUsuario", [id_usuario])
    if not result_sets or not result_sets[0]:
        return None

    return result_sets[0][0]["IdEmpleado"]


def consultar_planilla_semanal(id_empleado, id_semana=None):
    return call_procedure("sp_WebConsultarPlanillaSemanal", [id_empleado, id_semana])


def consultar_deducciones_semana(id_empleado, id_semana=None):
    return call_procedure("sp_WebConsultarDetalleDeduccionesSemana", [id_empleado, id_semana])


def consultar_horas_semana(id_empleado, id_semana=None):
    return call_procedure("sp_WebConsultarDetalleHorasSemana", [id_empleado, id_semana])


def consultar_planilla_mensual(id_empleado, id_mes=None):
    return call_procedure("sp_WebConsultarPlanillaMensual", [id_empleado, id_mes])


def consultar_deducciones_mes(id_empleado, id_mes=None):
    return call_procedure("sp_WebConsultarDetalleDeduccionesMes", [id_empleado, id_mes])


@empleado_bp.route("/planilla-semanal")
@login_required
def planilla_semanal():
    id_semana = request.args.get("id_semana", type=int)
    cantidad = request.args.get("cantidad", default=5, type=int)
    detalle = request.args.get("detalle")
    detalle_semana = request.args.get("detalle_semana", type=int)
    id_empleado = obtener_id_empleado_actual()
    planillas = []
    deducciones = []
    horas = []
    result_code = None

    if cantidad is None or cantidad < 1:
        cantidad = 5
    if cantidad > 50:
        cantidad = 50
    if detalle not in ("bruto", "deducciones"):
        detalle = None
        detalle_semana = None

    try:
        if id_empleado is None:
            if session.get("tipo_usuario") == 1:
                flash("Seleccione un empleado para impersonar.", "error")
                return redirect(url_for("admin.empleados"))

            id_empleado = obtener_id_empleado(session.get("id_usuario"))
            session["id_empleado"] = id_empleado

        resumen_sets, resumen_output = consultar_planilla_semanal(id_empleado, id_semana)
        planillas = resumen_sets[0] if resumen_sets else []
        planillas = planillas[:cantidad]
        result_code = resumen_output.get("ResultCode")
        log_event(
            11,
            {
                "accion": "consultar_planilla_semanal",
                "idEmpleado": id_empleado,
                "idSemana": id_semana,
                "cantidad": cantidad,
                "detalle": detalle,
                "detalleSemana": detalle_semana,
                "resultCode": result_code,
            },
        )

        if detalle == "bruto" and detalle_semana is not None:
            horas_sets, _ = consultar_horas_semana(id_empleado, detalle_semana)
            horas = horas_sets[0] if horas_sets else []

        if detalle == "deducciones" and detalle_semana is not None:
            deducciones_sets, _ = consultar_deducciones_semana(id_empleado, detalle_semana)
            deducciones = deducciones_sets[0] if deducciones_sets else []
    except Exception as exc:
        flash(str(exc), "error")

    return render_template(
        "empleado/planilla_semanal.html",
        id_empleado=id_empleado,
        id_semana=id_semana,
        cantidad=cantidad,
        detalle=detalle,
        detalle_semana=detalle_semana,
        planillas=planillas,
        deducciones=deducciones,
        horas=horas,
        result_code=result_code,
    )


@empleado_bp.route("/planilla-mensual")
@login_required
def planilla_mensual():
    id_mes = request.args.get("id_mes", type=int)
    cantidad = request.args.get("cantidad", default=5, type=int)
    detalle = request.args.get("detalle")
    detalle_mes = request.args.get("detalle_mes", type=int)
    id_empleado = obtener_id_empleado_actual()
    planillas = []
    deducciones = []
    result_code = None

    if cantidad is None or cantidad < 1:
        cantidad = 5
    if cantidad > 50:
        cantidad = 50
    if detalle != "deducciones":
        detalle = None
        detalle_mes = None

    try:
        if id_empleado is None:
            if session.get("tipo_usuario") == 1:
                flash("Seleccione un empleado para impersonar.", "error")
                return redirect(url_for("admin.empleados"))

            id_empleado = obtener_id_empleado(session.get("id_usuario"))
            session["id_empleado"] = id_empleado

        resumen_sets, resumen_output = consultar_planilla_mensual(id_empleado, id_mes)
        planillas = resumen_sets[0] if resumen_sets else []
        planillas = planillas[:cantidad]
        result_code = resumen_output.get("ResultCode")
        log_event(
            11,
            {
                "accion": "consultar_planilla_mensual",
                "idEmpleado": id_empleado,
                "idMes": id_mes,
                "cantidad": cantidad,
                "detalle": detalle,
                "detalleMes": detalle_mes,
                "resultCode": result_code,
            },
        )

        if detalle == "deducciones" and detalle_mes is not None:
            deducciones_sets, _ = consultar_deducciones_mes(id_empleado, detalle_mes)
            deducciones = deducciones_sets[0] if deducciones_sets else []
    except Exception as exc:
        flash(str(exc), "error")

    return render_template(
        "empleado/planilla_mensual.html",
        id_empleado=id_empleado,
        id_mes=id_mes,
        cantidad=cantidad,
        detalle=detalle,
        detalle_mes=detalle_mes,
        planillas=planillas,
        deducciones=deducciones,
        result_code=result_code,
    )
