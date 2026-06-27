USE PlanillaObrera;
GO

SET ANSI_NULLS ON;
GO

SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('dbo.sp_ConsultarDetalleDeduccionesMes', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_ConsultarDetalleDeduccionesMes;
GO

IF OBJECT_ID('dbo.sp_WebConsultarDetalleDeduccionesMes', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_WebConsultarDetalleDeduccionesMes;
GO

IF OBJECT_ID('dbo.sp_WebConsultarPlanillaMensual', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_WebConsultarPlanillaMensual;
GO

IF OBJECT_ID('dbo.sp_WebConsultarDetalleHorasSemana', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_WebConsultarDetalleHorasSemana;
GO

IF OBJECT_ID('dbo.sp_WebConsultarDetalleDeduccionesSemana', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_WebConsultarDetalleDeduccionesSemana;
GO

IF OBJECT_ID('dbo.sp_WebConsultarPlanillaSemanal', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_WebConsultarPlanillaSemanal;
GO

IF OBJECT_ID('dbo.sp_WebRegistrarEventoBitacora', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_WebRegistrarEventoBitacora;
GO

IF OBJECT_ID('dbo.sp_WebEliminarEmpleado', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_WebEliminarEmpleado;
GO

IF OBJECT_ID('dbo.sp_WebActualizarEmpleado', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_WebActualizarEmpleado;
GO

IF OBJECT_ID('dbo.sp_WebInsertarEmpleado', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_WebInsertarEmpleado;
GO

IF OBJECT_ID('dbo.sp_WebListarPuestos', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_WebListarPuestos;
GO

IF OBJECT_ID('dbo.sp_WebObtenerEmpleadoPorUsuario', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_WebObtenerEmpleadoPorUsuario;
GO

IF OBJECT_ID('dbo.sp_WebObtenerEmpleado', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_WebObtenerEmpleado;
GO

IF OBJECT_ID('dbo.sp_WebListarEmpleadosConFiltro', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_WebListarEmpleadosConFiltro;
GO

IF OBJECT_ID('dbo.sp_WebLogin', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_WebLogin;
GO

IF OBJECT_ID('dbo.sp_ConsultarPlanillaMensual', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_ConsultarPlanillaMensual;
GO

IF OBJECT_ID('dbo.sp_ConsultarDetalleHorasSemana', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_ConsultarDetalleHorasSemana;
GO

IF OBJECT_ID('dbo.sp_ConsultarDetalleDeduccionesSemana', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_ConsultarDetalleDeduccionesSemana;
GO

IF OBJECT_ID('dbo.sp_ConsultarPlanillaSemanal', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_ConsultarPlanillaSemanal;
GO

IF OBJECT_ID('dbo.sp_ActualizarEmpleado', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_ActualizarEmpleado;
GO

IF OBJECT_ID('dbo.sp_ObtenerEmpleado', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_ObtenerEmpleado;
GO

IF OBJECT_ID('dbo.sp_ListarEmpleadosConFiltro', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_ListarEmpleadosConFiltro;
GO

IF OBJECT_ID('dbo.sp_ListarEmpleados', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_ListarEmpleados;
GO

IF OBJECT_ID('dbo.sp_Login', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_Login;
GO

CREATE PROCEDURE dbo.sp_Login
    @inUsername VARCHAR(50)
  ,@inPassword VARCHAR(255)
  ,@inIPOrigen VARCHAR(45) = '127.0.0.1'
  ,@outIdUsuario INT OUTPUT
  ,@outTipoUsuario TINYINT OUTPUT
  ,@outResultCode INT OUTPUT
