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
            -- 3a. Deducciones PORCENTUALES (se aplican sobre el salario bruto semanal)
            DECLARE @IdTipoDedPct   INT;
            DECLARE @PorcentajeDed  DECIMAL(10,4);
            DECLARE @MontoDed       DECIMAL(12,2);
            DECLARE @IdTipoMovDed   INT;

            DECLARE cur_pct CURSOR LOCAL FAST_FORWARD FOR
                SELECT de.IdTipoDeduccion, td.Valor
                FROM dbo.DeduccionEmpleado de
                INNER JOIN dbo.TipoDeduccion td ON de.IdTipoDeduccion = td.IdTipoDeduccion
                WHERE de.IdEmpleado       = @IdEmpleado
                  AND td.Porcentual       = 1
                  AND de.FechaInicio     <= @FechaJueves
                  AND (de.FechaFin IS NULL OR de.FechaFin >= @FechaJueves);

            OPEN cur_pct;
            FETCH NEXT FROM cur_pct INTO @IdTipoDedPct, @PorcentajeDed;
            WHILE @@FETCH_STATUS = 0
            BEGIN
                SET @MontoDed = ROUND(@SalarioBruto * @PorcentajeDed, 2);
                SET @TotalDeducciones = @TotalDeducciones + @MontoDed;

                -- Movimiento débito (IdTipoMovimiento 4 en adelante según catálogo)
                -- Usamos el IdTipoDeduccion+3 como convención inicial; ajustar según catálogo real
                INSERT INTO dbo.MovimientoPlanilla (IdPlanillaSemXEmpleado, IdTipoMovimiento, IdMarcaAsistencia, Fecha, Cantidad, Monto)
                VALUES (@IdPlanillaSemXEmpleado, @IdTipoDedPct + 3, NULL, @FechaJueves, 0, -@MontoDed);

                -- Acumular en detalle mensual
                IF @IdPlanillaMesXEmpleado IS NOT NULL
                BEGIN
                    IF EXISTS (SELECT 1 FROM dbo.DeduccionXEmpleadoXMes WHERE IdPlanillaMesXEmpleado = @IdPlanillaMesXEmpleado AND IdTipoDeduccion = @IdTipoDedPct)
                        UPDATE dbo.DeduccionXEmpleadoXMes
                        SET MontoTotal = MontoTotal + @MontoDed
                        WHERE IdPlanillaMesXEmpleado = @IdPlanillaMesXEmpleado AND IdTipoDeduccion = @IdTipoDedPct;
                    ELSE
                        INSERT INTO dbo.DeduccionXEmpleadoXMes (IdPlanillaMesXEmpleado, IdTipoDeduccion, MontoTotal)
                        VALUES (@IdPlanillaMesXEmpleado, @IdTipoDedPct, @MontoDed);
                END;

                FETCH NEXT FROM cur_pct INTO @IdTipoDedPct, @PorcentajeDed;
            END;
            CLOSE cur_pct; DEALLOCATE cur_pct;
            -- 3b. Deducciones FIJAS (monto mensual dividido entre 4 o 5 jueves)
            DECLARE @IdTipoDedFija  INT;
            DECLARE @MontoFijo      DECIMAL(12,2);
            DECLARE @MontoSemanal   DECIMAL(12,2);

            DECLARE cur_fija CURSOR LOCAL FAST_FORWARD FOR
                SELECT de.IdTipoDeduccion, de.MontoFijo
                FROM dbo.DeduccionEmpleado de
                INNER JOIN dbo.TipoDeduccion td ON de.IdTipoDeduccion = td.IdTipoDeduccion
                WHERE de.IdEmpleado       = @IdEmpleado
                  AND td.Porcentual       = 0
                  AND de.MontoFijo        > 0
                  AND de.FechaInicio     <= @FechaJueves
                  AND (de.FechaFin IS NULL OR de.FechaFin >= @FechaJueves);

            OPEN cur_fija;
            FETCH NEXT FROM cur_fija INTO @IdTipoDedFija, @MontoFijo;
            WHILE @@FETCH_STATUS = 0
            BEGIN
                SET @MontoSemanal = ROUND(@MontoFijo / @CantidadJueves, 2);
                SET @TotalDeducciones = @TotalDeducciones + @MontoSemanal;

                INSERT INTO dbo.MovimientoPlanilla (IdPlanillaSemXEmpleado, IdTipoMovimiento, IdMarcaAsistencia, Fecha, Cantidad, Monto)
                VALUES (@IdPlanillaSemXEmpleado, @IdTipoDedFija + 3, NULL, @FechaJueves, 0, -@MontoSemanal);

                IF @IdPlanillaMesXEmpleado IS NOT NULL
                BEGIN
                    IF EXISTS (SELECT 1 FROM dbo.DeduccionXEmpleadoXMes WHERE IdPlanillaMesXEmpleado = @IdPlanillaMesXEmpleado AND IdTipoDeduccion = @IdTipoDedFija)
                        UPDATE dbo.DeduccionXEmpleadoXMes
                        SET MontoTotal = MontoTotal + @MontoSemanal
                        WHERE IdPlanillaMesXEmpleado = @IdPlanillaMesXEmpleado AND IdTipoDeduccion = @IdTipoDedFija;
                    ELSE
                        INSERT INTO dbo.DeduccionXEmpleadoXMes (IdPlanillaMesXEmpleado, IdTipoDeduccion, MontoTotal)
                        VALUES (@IdPlanillaMesXEmpleado, @IdTipoDedFija, @MontoSemanal);
                END;

                FETCH NEXT FROM cur_fija INTO @IdTipoDedFija, @MontoFijo;
            END;
            CLOSE cur_fija; DEALLOCATE cur_fija;
            -- 3c. Actualizar planilla semanal del empleado
            UPDATE dbo.PlanillaSemXEmpleado
            SET
                TotalDeducciones = @TotalDeducciones,
                SalarioNeto      = SalarioBruto - @TotalDeducciones,
                Procesada        = 1
            WHERE IdPlanillaSemXEmpleado = @IdPlanillaSemXEmpleado;
