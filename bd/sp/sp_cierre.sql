-- ============================================================
-- SP_CIERRE: Cierre semanal, apertura de semana y apertura de mes
-- Se ejecutan cada jueves a medianoche
-- ============================================================

USE PlanillaObrera;
GO

-- ============================================================
-- SP: Cierre semanal - aplica deducciones y calcula salario neto
-- Se llama cada jueves para la semana que TERMINA ese jueves.
-- ============================================================
IF OBJECT_ID('sp_CierreSemanal', 'P') IS NOT NULL DROP PROCEDURE sp_CierreSemanal;
GO
CREATE PROCEDURE sp_CierreSemanal
    @FechaJueves        DATE,           -- Fecha del jueves de cierre
    @IdUsuarioSistema   INT,
    @IPOrigen           VARCHAR(45) = '127.0.0.1'
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        BEGIN TRANSACTION;
        -- 1. Obtener la semana planilla que cierra en este jueves
        DECLARE @IdSemanaPlanilla INT;
        SELECT @IdSemanaPlanilla = IdSemanaPlanilla
        FROM dbo.SemanaPlanilla
        WHERE FechaFin = @FechaJueves AND Cerrada = 0;

        IF @IdSemanaPlanilla IS NULL
        BEGIN
            RAISERROR('No hay semana planilla abierta que cierre el %s.', 16, 1, CONVERT(VARCHAR,@FechaJueves,103));
            ROLLBACK; RETURN;
        END;
        -- 2. Obtener el mes planilla al que pertenece esta semana
        DECLARE @IdMesPlanilla  INT;
        DECLARE @CantidadJueves TINYINT;

        SELECT
            @IdMesPlanilla  = sp.IdMesPlanilla,
            @CantidadJueves = mp.CantidadJueves
        FROM dbo.SemanaPlanilla sp
        INNER JOIN dbo.MesPlanilla mp ON sp.IdMesPlanilla = mp.IdMesPlanilla
        WHERE sp.IdSemanaPlanilla = @IdSemanaPlanilla;
        -- 3. Procesar cada empleado activo con planilla semanal en esta semana
        DECLARE @IdEmpleado             INT;
        DECLARE @IdPlanillaSemXEmpleado INT;
        DECLARE @SalarioBruto           DECIMAL(14,2);
        DECLARE @TotalDeducciones       DECIMAL(14,2);

        DECLARE cur_empleados CURSOR LOCAL FAST_FORWARD FOR
            SELECT pse.IdPlanillaSemXEmpleado, pse.IdEmpleado, pse.SalarioBruto
            FROM dbo.PlanillaSemXEmpleado pse
            WHERE pse.IdSemanaPlanilla = @IdSemanaPlanilla
              AND pse.Procesada = 0;

        OPEN cur_empleados;
        FETCH NEXT FROM cur_empleados INTO @IdPlanillaSemXEmpleado, @IdEmpleado, @SalarioBruto;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @TotalDeducciones = 0;

            -- Obtener IdPlanillaMesXEmpleado
            DECLARE @IdPlanillaMesXEmpleado INT;
            SELECT @IdPlanillaMesXEmpleado = IdPlanillaMesXEmpleado
            FROM dbo.PlanillaMesXEmpleado
            WHERE IdMesPlanilla = @IdMesPlanilla AND IdEmpleado = @IdEmpleado;
