from flask import Blueprint, flash, redirect, render_template, request, session, url_for

from routes.auth import admin_required, call_procedure, log_event


admin_bp=Blueprint("admin", __name__)


#EmpleadosAdmin
def listar_empleados(nombre=None, documento=None):
    result_sets, output=call_procedure(
        "sp_WebListarEmpleadosConFiltro",
        [nombre, documento, 1, None, None],
    )
    empleados=result_sets[0] if result_sets else []
    return empleados, output.get("ResultCode")


def obtener_empleado(id_empleado):
    result_sets, output=call_procedure("sp_WebObtenerEmpleado", [id_empleado, None])
    empleados=result_sets[0] if result_sets else []
    empleado=empleados[0] if empleados else None
    return empleado, output.get("ResultCode")


def listar_puestos():
    result_sets, output=call_procedure("sp_WebListarPuestos")
    puestos=result_sets[0] if result_sets else []
    return puestos, output.get("ResultCode")


#FormularioEmpleado
def leer_formulario_empleado():
    return {
        "Nombre": request.form.get("nombre", "").strip(),
        "ValorDocumentoIdentidad": request.form.get("valor_documento", "").strip(),
        "NombrePuesto": request.form.get("nombre_puesto", "").strip(),
        "Username": request.form.get("username", "").strip(),
        "Password": request.form.get("password", "").strip(),
        "CuentaBancaria": request.form.get("cuenta_bancaria", "").strip() or None,
        "FechaIngreso": request.form.get("fecha_ingreso", "").strip(),
        "Activo": 1 if request.form.get("activo") == "on" else 0,
    }


#CRUDEmpleado
def insertar_empleado(datos):
    _, output=call_procedure(
        "sp_WebInsertarEmpleado",
        [
            datos["Nombre"],
            datos["ValorDocumentoIdentidad"],
            datos["NombrePuesto"],
            datos["Username"],
            datos["Password"],
            datos["CuentaBancaria"],
            datos["FechaIngreso"],
            session.get("id_usuario"),
            request.remote_addr or "127.0.0.1",
        ],
    )
    return output


def actualizar_empleado(id_empleado, datos):
    _, output=call_procedure(
        "sp_WebActualizarEmpleado",
        [
            id_empleado,
            datos["Nombre"],
            datos["ValorDocumentoIdentidad"],
            datos["NombrePuesto"],
            datos["Username"],
            datos["Password"] or None,
            datos["CuentaBancaria"],
            datos["FechaIngreso"],
            datos["Activo"],
            session.get("id_usuario"),
            request.remote_addr or "127.0.0.1",
        ],
    )
    return output


def eliminar_empleado(valor_documento):
    _, output=call_procedure(
        "sp_WebEliminarEmpleado",
        [
            valor_documento,
            session.get("id_usuario"),
            request.remote_addr or "127.0.0.1",
        ],
    )
    return output


@admin_bp.route("/empleados")
@admin_required
def empleados():
    nombre=request.args.get("nombre") or None
    documento=request.args.get("documento") or None
    empleados_data=[]
    result_code=None

    try:
        empleados_data, result_code=listar_empleados(nombre, documento)
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


@admin_bp.route("/empleados/nuevo", methods=["GET", "POST"])
@admin_required
def nuevo_empleado():
    puestos, _=listar_puestos()
    empleado={
        "Activo": 1,
    }

    if request.method == "POST":
        empleado=leer_formulario_empleado()
        output=insertar_empleado(empleado)
        result_code=output.get("ResultCode")

        if result_code == 0:
            flash("Empleado creado correctamente.", "info")
            return redirect(url_for("admin.empleados"))

        flash(f"No se pudo crear el empleado. ResultCode: {result_code}", "error")

    return render_template(
        "admin/empleado_form.html",
        modo="nuevo",
        empleado=empleado,
        puestos=puestos,
        result_code=None,
    )


@admin_bp.route("/empleados/<int:id_empleado>/editar", methods=["GET", "POST"])
@admin_required
def editar_empleado(id_empleado):
    puestos, _=listar_puestos()
    empleado, result_code=obtener_empleado(id_empleado)

    if empleado is None:
        flash(f"No se encontró el empleado. ResultCode: {result_code}", "error")
        return redirect(url_for("admin.empleados"))

    if request.method == "POST":
        datos=leer_formulario_empleado()
        output=actualizar_empleado(id_empleado, datos)
        result_code=output.get("ResultCode")

        if result_code == 0:
            flash("Empleado actualizado correctamente.", "info")
            return redirect(url_for("admin.empleados"))

        flash(f"No se pudo actualizar el empleado. ResultCode: {result_code}", "error")
        empleado.update(datos)

    return render_template(
        "admin/empleado_form.html",
        modo="editar",
        empleado=empleado,
        puestos=puestos,
        result_code=result_code,
    )


@admin_bp.route("/empleados/<int:id_empleado>/eliminar", methods=["POST"])
@admin_required
def eliminar_empleado_route(id_empleado):
    empleado, result_code=obtener_empleado(id_empleado)

    if empleado is None:
        flash(f"No se encontró el empleado. ResultCode: {result_code}", "error")
        return redirect(url_for("admin.empleados"))

    output=eliminar_empleado(empleado["ValorDocumentoIdentidad"])
    result_code=output.get("ResultCode")

    if result_code == 0:
        flash("Empleado eliminado correctamente.", "info")
    else:
        flash(f"No se pudo eliminar el empleado. ResultCode: {result_code}", "error")

    return redirect(url_for("admin.empleados"))


@admin_bp.route("/impersonar/<int:id_empleado>", methods=["POST"])
@admin_required
def impersonar_empleado(id_empleado):
    try:
        empleado, result_code=obtener_empleado(id_empleado)
    except Exception as exc:
        flash(str(exc), "error")
        return redirect(url_for("admin.empleados"))

    if result_code != 0 or empleado is None:
        flash(f"No se pudo impersonar el empleado. ResultCode: {result_code}", "error")
        return redirect(url_for("admin.empleados"))

    session["id_empleado_impersonado"]=empleado["IdEmpleado"]
    session["nombre_empleado_impersonado"]=empleado["Nombre"]
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
