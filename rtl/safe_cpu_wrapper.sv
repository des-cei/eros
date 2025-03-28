// Copyright 2025 CEI UPM
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
// Luis Waucquez (luis.waucquez.jimenez@upm.es)

module safe_cpu_wrapper
  import obi_pkg::*;
  import reg_pkg::*;
  import cei_mochila_pkg::*;
#(
    parameter NHARTS  = 3,
    parameter NCYCLES = 1
) (
    // Clock and Reset
    input logic clk_i,
    input logic rst_ni,

    // Instruction memory interface 
    output obi_req_t  [NHARTS-1 : 0] core_instr_req_o,
    input  obi_resp_t [NHARTS-1 : 0] core_instr_resp_i,

    // Data memory interface 
    output obi_req_t  [NHARTS-1 : 0] core_data_req_o,
    input  obi_resp_t [NHARTS-1 : 0] core_data_resp_i,

    // OBI -> Memory mapped register control Safe CPU
    input  reg_req_t wrapper_csr_req_i,
    output reg_rsp_t wrapper_csr_resp_o,

    // Debug Interface
    input  logic              debug_req_i,
    output logic [NHARTS-1:0] sleep_o,

    //External Interrupt
    output logic interrupt_o
);

  localparam NRCOMPARATORS = NHARTS == 3 ? 3 : 1;

  //Signals//

  logic bus_config_s;

  logic [NHARTS-1:0][31:0] intr;
  logic [NHARTS-1:0][31:0] mux_intr_i;
  logic [NHARTS-1:0][31:0] mux_intr_o;

  logic [NHARTS-1:0] debug_req;
  logic [NHARTS-1:0] mux_debug_req_i;
  logic [NHARTS-1:0] mux_debug_req_o;

  logic en_ext_debug_s;
  logic Initial_Sync_Master_s;
  logic [NHARTS-1:0] Hart_ack_s;
  logic [NHARTS-1:0] Hart_wfi_s;
  logic [NHARTS-1:0] Hart_intc_ack_s;
  logic [NHARTS-1:0] Interrupt_swResync_s;
  logic [NHARTS-1:0] Interrupt_DMSH_Sync_s;
  logic [NHARTS-1:0] master_core_s;
  logic [NHARTS-1:0] master_core_ff_s;
  logic [2:0] safe_mode_s;
  logic [1:0] safe_configuration_s;
  logic critical_section_s;
  logic [NHARTS-1:0] intc_sync_s;
  logic [NHARTS-1:0] intc_halt_s;
  logic [NHARTS-1:0] sleep_s;
  logic [NHARTS-1:0] debug_mode_s;
  logic End_sw_routine_s;
  logic Start_s;
  logic Start_Boot_s;
  logic DMR_Rec_s;

  // CPU ports
  obi_req_t [NHARTS-1 : 0] core_instr_req;
  obi_resp_t [NHARTS-1 : 0] core_instr_resp;

  obi_req_t [NHARTS-1 : 0] core_data_req;
  obi_resp_t [NHARTS-1 : 0] core_data_resp;

  // Muxed Input CPU ports
  obi_req_t [NHARTS-1 : 0] mux_core_instr_req_i;
  obi_resp_t [NHARTS-1 : 0] mux_core_instr_resp_i;

  obi_req_t [NHARTS-1 : 0] mux_core_data_req_i;
  obi_resp_t [NHARTS-1 : 0] mux_core_data_resp_i;

  // Muxed Output CPU ports
  obi_req_t [NHARTS-1 : 0] mux_core_instr_req_o;
  obi_resp_t [NHARTS-1 : 0] mux_core_instr_resp_o;

  obi_req_t [NHARTS-1 : 0] mux_core_data_req_o;
  obi_resp_t [NHARTS-1 : 0] mux_core_data_resp_o;

  // XBAR_CPU Slaves Signals
  obi_req_t [NHARTS-1 : 0][1:0] xbar_core_data_req;
  obi_resp_t [NHARTS-1 : 0][1:0] xbar_core_data_resp;

  // Voted_CPU Signals
  obi_req_t [NHARTS-1 : 0] voted_core_instr_req_o;
  obi_req_t [NHARTS-1 : 0] voted_core_data_req_o;
  logic [NHARTS-1:0] tmr_error_s;
  logic [2:0] dmr_error_s;
  logic [NHARTS-1:0][2:0] tmr_errorid_s;
  logic tmr_voter_enable_s;
  logic [2:0] dmr_config_s;
  logic dual_mode_s;
  logic delayed_s;
  logic [NHARTS-1:0] dmr_wfi_s;

  // Compared CPU Signals
  obi_req_t [NRCOMPARATORS-1:0] compared_core_instr_req_o;
  obi_req_t [NRCOMPARATORS-1:0] compared_core_data_req_o;

  // CPU Private Regs
  reg_pkg::reg_req_t [NHARTS-1 : 0] cpu_reg_req;
  reg_pkg::reg_rsp_t [NHARTS-1 : 0] cpu_reg_rsp;

  // Safe CPU reg port
  reg_pkg::reg_req_t safe_cpu_wrapper_reg_req;
  reg_pkg::reg_rsp_t safe_cpu_wrapper_reg_rsp;


  // Configuration IDs Cores

  logic [2:0][NHARTS-1:0] Core_ID;
  assign Core_ID[0] = {3'b001};
  assign Core_ID[1] = {3'b010};
  assign Core_ID[2] = {3'b100};

  //Isolate val bus
  // Instruction memory interface 
  obi_resp_t [NHARTS-1 : 0] isolate_core_instr_resp;

  // Data memory interface 
  obi_resp_t [NHARTS-1 : 0] isolate_core_data_resp;


  //***Cores System***//

  cpu_system cpu_system_i (
      .clk_i,
      .rst_ni,
      // Instruction memory interface
      .core_instr_req_o (core_instr_req),
      .core_instr_resp_i(core_instr_resp),

      // Data memory interface
      .core_data_req_o (core_data_req),
      .core_data_resp_i(core_data_resp),

      // Interrupt
      //Core 0
      .intc_core0(mux_intr_o[0]),
      //Core 1
      .intc_core1(mux_intr_o[1]),

      //Core 2
      .intc_core2(mux_intr_o[2]),


      .sleep_o(sleep_s),

      // Debug Interface
      .debug_req_i (mux_debug_req_o),
      .debug_mode_o(debug_mode_s)
  );

  assign sleep_o = sleep_s;

  safe_wrapper_ctrl #(
      .reg_req_t(reg_pkg::reg_req_t),
      .reg_rsp_t(reg_pkg::reg_rsp_t)
  ) safe_wrapper_ctrl_i (
      .clk_i,
      .rst_ni,

      // Bus Interface
      .reg_req_i(wrapper_csr_req_i),
      .reg_rsp_o(wrapper_csr_resp_o),

      .master_core_o(master_core_s),
      .safe_mode_o(safe_mode_s),
      .safe_configuration_o(safe_configuration_s),
      .critical_section_o(critical_section_s),
      .Initial_Sync_Master_o(Initial_Sync_Master_s),
      .Start_o(Start_s),
      .End_sw_routine_o(End_sw_routine_s),
      .interrupt_o(interrupt_o),
      .debug_mode_i(debug_mode_s),
      .sleep_i(sleep_s),
      .Start_Boot_i(Start_Boot_s),
      .DMR_Rec_i(DMR_Rec_s),
      //.Debug_ext_req_i(debug_req_i), //Check if debug_req comes from FSM or external debug Todo: change to 1 the extenal req
      .en_ext_debug_i(en_ext_debug_s)  //Todo: other more elegant solution for debugging
  );


  //***Safe FSM***//

  safe_FSM safe_FSM_i (
      // Clock and Reset
      .clk_i,
      .rst_ni,
      .tmr_critical_section_i(critical_section_s),
      .DMR_Mask_i(safe_mode_s),
      .Safe_configuration_i(safe_configuration_s),
      .Initial_Sync_Master_i(Initial_Sync_Master_s),
      .Halt_ack_i(debug_mode_s),
      .Hart_wfi_i(sleep_s),
      .Hart_intc_ack_i(Hart_intc_ack_s),
      .Master_Core_i(master_core_s),
      .Interrupt_Sync_o(intc_sync_s),
      .Interrupt_swResync_o(Interrupt_swResync_s),
      .Interrupt_Halt_o(intc_halt_s),
      .tmr_error_i(tmr_error_s[0] | tmr_error_s[1] | tmr_error_s[2]),
      .voter_id_error(tmr_errorid_s[0] | tmr_errorid_s[1] | tmr_errorid_s[2]),
      .Single_Bus_o(bus_config_s),
      .Tmr_voter_enable_o(tmr_voter_enable_s),
      .Dmr_comparator_enable_o(dual_mode_s),
      .Dmr_config_o(dmr_config_s),
      .dmr_error_i(dmr_error_s),
      .wfi_dmr_o(dmr_wfi_s),
      .Delayed_o(delayed_s),
      .Start_Boot_o(Start_Boot_s),
      .Start_i(Start_s),
      .End_sw_routine_i(End_sw_routine_s),
      .DMR_Rec_o(DMR_Rec_s),
      .en_ext_debug_req_o(en_ext_debug_s)
  );
  assign intr[0] = {12'b0, 1'b0, 1'b0, intc_sync_s[0], 1'b0, 16'b0};
  assign intr[1] = {12'b0, 1'b0, 1'b0, intc_sync_s[1], 1'b0, 16'b0};
  assign intr[2] = {12'b0, 1'b0, 1'b0, intc_sync_s[2], 1'b0, 16'b0};

  //Todo: future posibility to debug during TMR_SYNC or DMR_SYNC
  assign debug_req[0] = (debug_req_i && en_ext_debug_s && master_core_s[0]) || intc_halt_s[0];
  assign debug_req[1] = (debug_req_i && en_ext_debug_s && master_core_s[1]) || intc_halt_s[1];
  assign debug_req[2] = (debug_req_i && en_ext_debug_s && master_core_s[2]) || intc_halt_s[2];


  //*****************Safety_Multiplexer*********************//
  always @(*) begin

    if (bus_config_s == 0) begin
      //Instruction
      core_instr_req_o        = mux_core_instr_req_o;
      mux_core_instr_resp_i   = core_instr_resp_i;

      //Data
      core_data_req_o         = mux_core_data_req_o;
      mux_core_data_resp_i[0] = core_data_resp_i[0];
      mux_core_data_resp_i[1] = core_data_resp_i[1];
      mux_core_data_resp_i[2] = core_data_resp_i[2];
    end else begin
      /////***///// Avoid latch
      //Instruction
      core_instr_req_o[0] = compared_core_instr_req_o[0];
      core_instr_req_o[1] = '0;
      core_instr_req_o[2] = '0;
      mux_core_instr_resp_i[0] = core_instr_resp_i[0];
      mux_core_instr_resp_i[1] = core_instr_resp_i[0];
      mux_core_instr_resp_i[2] = core_instr_resp_i[0];
      //Data
      core_data_req_o[0] = compared_core_data_req_o[0];
      core_data_req_o[1] = '0;
      core_data_req_o[2] = '0;
      mux_core_data_resp_i[0] = core_data_resp_i[0];
      mux_core_data_resp_i[1] = core_data_resp_i[0];
      mux_core_data_resp_i[2] = core_data_resp_i[0];
      /////***/////

      //TMR_Config_Default    //Todo Depends on FSM output
      //            if (tmr_voter_enable_s == 1'b1) begin
      if (tmr_voter_enable_s == 1'b1 && dual_mode_s == 1'b0) begin
        //Instruction
        if (master_core_ff_s == 3'b001) begin
          core_instr_req_o[0] = voted_core_instr_req_o[0];
          core_instr_req_o[1] = '0;
          core_instr_req_o[2] = '0;
        end else if (master_core_ff_s == 3'b010) begin
          core_instr_req_o[0] = '0;
          core_instr_req_o[1] = voted_core_instr_req_o[1];
          core_instr_req_o[2] = '0;
        end else begin
          core_instr_req_o[0] = '0;
          core_instr_req_o[1] = '0;
          core_instr_req_o[2] = voted_core_instr_req_o[2];
        end


        if (master_core_ff_s == 3'b001) begin
          mux_core_instr_resp_i[0] = core_instr_resp_i[0];
          mux_core_instr_resp_i[1] = core_instr_resp_i[0];
          mux_core_instr_resp_i[2] = core_instr_resp_i[0];
        end else if (master_core_ff_s == 3'b010) begin
          mux_core_instr_resp_i[0] = core_instr_resp_i[1];
          mux_core_instr_resp_i[1] = core_instr_resp_i[1];
          mux_core_instr_resp_i[2] = core_instr_resp_i[1];
        end else begin
          mux_core_instr_resp_i[0] = core_instr_resp_i[2];
          mux_core_instr_resp_i[1] = core_instr_resp_i[2];
          mux_core_instr_resp_i[2] = core_instr_resp_i[2];
        end

        //Dynamic isolation from TCLS, not ready yet
        /*
                    if (Select_wfi_core_s == 3'b001) begin
                        mux_core_instr_resp_i[0].rvalid = 1'b1;
                        mux_core_instr_resp_i[0].gnt = 1'b1;
                        mux_core_instr_resp_i[0].rdata = 32'h10500073; //wfi instruction

                        if (master_core_s == 3'b001) begin
                        mux_core_instr_resp_i[1] = core_instr_resp_i[0];
                        end else if (master_core_s == 3'b010) begin
                        mux_core_instr_resp_i[2] = core_instr_resp_i[0];
                    end 
                    else if (Select_wfi_core_s == 3'b010) begin
                        mux_core_instr_resp_i[1].rvalid = 1'b1;
                        mux_core_instr_resp_i[1].gnt = 1'b1;
                        mux_core_instr_resp_i[1].rdata = 32'h10500073; //wfi instruction

                        mux_core_instr_resp_i[0] = core_instr_resp_i[0];
                        mux_core_instr_resp_i[2] = core_instr_resp_i[0];
                    end 
                    else if (Select_wfi_core_s == 3'b100) begin
                        mux_core_instr_resp_i[2].rvalid = 1'b1;
                        mux_core_instr_resp_i[2].gnt = 1'b1;
                        mux_core_instr_resp_i[2].rdata = 32'h10500073; //wfi instruction

                        mux_core_instr_resp_i[0] = core_instr_resp_i[0];
                        mux_core_instr_resp_i[1] = core_instr_resp_i[0];
                    end 
                    else begin 
                        mux_core_instr_resp_i[0] = core_instr_resp_i[0];
                        mux_core_instr_resp_i[1] = core_instr_resp_i[0];
                        mux_core_instr_resp_i[2] = core_instr_resp_i[0];  
                    end
                    */
        //Data
        if (master_core_ff_s == 3'b001) begin
          core_data_req_o[0] = voted_core_data_req_o[0];
          core_data_req_o[1] = '0;
          core_data_req_o[2] = '0;
          mux_core_data_resp_i[0] = core_data_resp_i[0];
          mux_core_data_resp_i[1] = core_data_resp_i[0];
          mux_core_data_resp_i[2] = core_data_resp_i[0];
        end else if (master_core_ff_s == 3'b010) begin
          core_data_req_o[0] = '0;
          core_data_req_o[1] = voted_core_data_req_o[1];
          core_data_req_o[2] = '0;
          mux_core_data_resp_i[0] = core_data_resp_i[1];
          mux_core_data_resp_i[1] = core_data_resp_i[1];
          mux_core_data_resp_i[2] = core_data_resp_i[1];
        end else begin
          core_data_req_o[0] = '0;
          core_data_req_o[1] = '0;
          core_data_req_o[2] = voted_core_data_req_o[2];
          mux_core_data_resp_i[0] = core_data_resp_i[2];
          mux_core_data_resp_i[1] = core_data_resp_i[2];
          mux_core_data_resp_i[2] = core_data_resp_i[2];
        end
      end else if (dual_mode_s == 1'b1) begin
        if (dmr_config_s == 3'b011) begin  //Comparator 0

          //Instruction
          if (master_core_ff_s == 3'b001) begin
            core_instr_req_o[0] = compared_core_instr_req_o[0];
            core_instr_req_o[1] = '0;
            core_instr_req_o[2] = mux_core_instr_req_o[2];
          end else begin
            core_instr_req_o[0] = '0;
            core_instr_req_o[1] = compared_core_instr_req_o[1];
            core_instr_req_o[2] = mux_core_instr_req_o[2];
          end

          if (dmr_wfi_s == 3'b011) begin
            core_instr_req_o[0] = '0;
            core_instr_req_o[1] = '0;
            core_instr_req_o[2] = '0;
            mux_core_instr_resp_i[2] = core_instr_resp_i[1];
            mux_core_instr_resp_i[0] = isolate_core_instr_resp[0];
            mux_core_instr_resp_i[1] = isolate_core_instr_resp[1];
          end else begin
            mux_core_instr_resp_i[2] = core_instr_resp_i[2];
            if (master_core_ff_s == 3'b001) begin
              mux_core_instr_resp_i[0] = core_instr_resp_i[0];
              mux_core_instr_resp_i[1] = core_instr_resp_i[0];
            end else begin
              mux_core_instr_resp_i[0] = core_instr_resp_i[1];
              mux_core_instr_resp_i[1] = core_instr_resp_i[1];
            end
          end
          //Data
          if (master_core_ff_s == 3'b001) begin
            core_data_req_o[0] = compared_core_data_req_o[0];
            core_data_req_o[1] = '0;
            core_data_req_o[2] = mux_core_instr_req_o[2];
          end else begin
            core_data_req_o[0] = '0;
            core_data_req_o[1] = compared_core_data_req_o[1];
            core_data_req_o[2] = mux_core_data_req_o[2];
          end

          if (dmr_wfi_s == 3'b011) begin
            core_data_req_o[0] = '0;
            core_data_req_o[1] = '0;
            core_data_req_o[2] = '0;

            mux_core_data_resp_i[0] = isolate_core_data_resp[0];
            mux_core_data_resp_i[1] = isolate_core_data_resp[1];
            mux_core_data_resp_i[2] = core_data_resp_i[1];
          end else begin
            mux_core_data_resp_i[2] = core_data_resp_i[2];
            if (master_core_ff_s == 3'b001) begin
              mux_core_data_resp_i[0] = core_data_resp_i[0];
              mux_core_data_resp_i[1] = core_data_resp_i[0];
            end else begin
              mux_core_data_resp_i[0] = core_data_resp_i[1];
              mux_core_data_resp_i[1] = core_data_resp_i[1];
            end
          end

        end else if (dmr_config_s == 3'b110) begin  //Comparator 1

          //Instruction
          if (master_core_ff_s == 3'b010) begin
            core_instr_req_o[0] = mux_core_instr_req_o[0];
            core_instr_req_o[1] = compared_core_instr_req_o[1];
            core_instr_req_o[2] = '0;
          end else begin
            core_instr_req_o[0] = mux_core_instr_req_o[0];
            core_instr_req_o[1] = '0;
            core_instr_req_o[2] = compared_core_instr_req_o[2];
          end

          if (dmr_wfi_s == 3'b110) begin
            core_instr_req_o[0] = '0;
            core_instr_req_o[1] = '0;
            core_instr_req_o[2] = '0;
            mux_core_instr_resp_i[0] = core_instr_resp_i[1];
            mux_core_instr_resp_i[1] = isolate_core_instr_resp[1];
            mux_core_instr_resp_i[2] = isolate_core_instr_resp[2];
          end else begin
            mux_core_instr_resp_i[0] = core_instr_resp_i[0];
            if (master_core_ff_s == 3'b010) begin
              mux_core_instr_resp_i[1] = core_instr_resp_i[1];
              mux_core_instr_resp_i[2] = core_instr_resp_i[1];
            end else begin
              mux_core_instr_resp_i[1] = core_instr_resp_i[2];
              mux_core_instr_resp_i[2] = core_instr_resp_i[2];
            end
          end

          //Data
          if (master_core_ff_s == 3'b010) begin
            core_data_req_o[0] = mux_core_data_req_o[0];
            core_data_req_o[1] = compared_core_data_req_o[1];
            core_data_req_o[2] = '0;
          end else begin
            core_data_req_o[0] = mux_core_data_req_o[0];
            core_data_req_o[1] = '0;
            core_data_req_o[2] = compared_core_data_req_o[2];
          end
          if (dmr_wfi_s == 3'b110) begin
            core_data_req_o[0] = '0;
            core_data_req_o[1] = '0;
            core_data_req_o[2] = '0;

            mux_core_data_resp_i[0] = core_data_resp_i[1];
            mux_core_data_resp_i[1] = isolate_core_data_resp[1];
            mux_core_data_resp_i[2] = isolate_core_data_resp[2];
          end else begin
            mux_core_data_resp_i[0] = core_data_resp_i[0];
            if (master_core_ff_s == 3'b010) begin
              mux_core_data_resp_i[1] = core_data_resp_i[1];
              mux_core_data_resp_i[2] = core_data_resp_i[1];
            end else begin
              mux_core_data_resp_i[1] = core_data_resp_i[2];
              mux_core_data_resp_i[2] = core_data_resp_i[2];
            end
          end
        end else begin  //Comparator 2
          //Instruction
          if (master_core_ff_s == 3'b100) begin
            core_instr_req_o[0] = '0;
            core_instr_req_o[1] = mux_core_instr_req_o[1];
            core_instr_req_o[2] = compared_core_instr_req_o[2];
          end else begin
            core_instr_req_o[0] = compared_core_instr_req_o[0];
            core_instr_req_o[1] = mux_core_instr_req_o[1];
            core_instr_req_o[2] = '0;
          end

          if (dmr_wfi_s == 3'b101) begin
            core_instr_req_o[0] = '0;
            core_instr_req_o[1] = '0;
            core_instr_req_o[2] = '0;
            mux_core_instr_resp_i[1] = core_instr_resp_i[1];
            mux_core_instr_resp_i[0] = isolate_core_instr_resp[0];
            mux_core_instr_resp_i[2] = isolate_core_instr_resp[2];
          end else begin
            mux_core_instr_resp_i[1] = core_instr_resp_i[1];
            if (master_core_ff_s == 3'b100) begin
              mux_core_instr_resp_i[0] = core_instr_resp_i[2];
              mux_core_instr_resp_i[2] = core_instr_resp_i[2];
            end else begin
              mux_core_instr_resp_i[0] = core_instr_resp_i[0];
              mux_core_instr_resp_i[2] = core_instr_resp_i[0];
            end
          end
          //Data
          if (master_core_ff_s == 3'b100) begin
            core_data_req_o[0] = '0;
            core_data_req_o[1] = mux_core_data_req_o[1];
            core_data_req_o[2] = compared_core_data_req_o[2];
          end else begin
            core_data_req_o[0] = compared_core_data_req_o[0];
            core_data_req_o[1] = mux_core_data_req_o[1];
            core_data_req_o[2] = '0;
          end
          if (dmr_wfi_s == 3'b101) begin
            mux_core_data_resp_i[0] = isolate_core_data_resp[0];
            mux_core_data_resp_i[1] = core_data_resp_i[1];
            mux_core_data_resp_i[2] = isolate_core_data_resp[2];
          end else begin
            mux_core_data_resp_i[1] = core_data_resp_i[1];
            if (master_core_ff_s == 3'b100) begin
              mux_core_data_resp_i[0] = core_data_resp_i[2];
              mux_core_data_resp_i[2] = core_data_resp_i[2];
            end else begin
              mux_core_data_resp_i[0] = core_data_resp_i[0];
              mux_core_data_resp_i[2] = core_data_resp_i[0];
            end
          end
        end
      end
    end
  end


  /*********************************************************************/
  /*********************Lockstep-Bypass Mux Reg*************************/

  assign mux_core_instr_req_i = core_instr_req;
  assign core_instr_resp = mux_core_instr_resp_o;
  assign mux_intr_i = intr;
  assign mux_debug_req_i = debug_req;

  assign mux_core_data_req_i[0] = xbar_core_data_req[0][0];
  assign mux_core_data_req_i[1] = xbar_core_data_req[1][0];
  assign mux_core_data_req_i[2] = xbar_core_data_req[2][0];
  assign xbar_core_data_resp[0][0] = mux_core_data_resp_o[0];
  assign xbar_core_data_resp[1][0] = mux_core_data_resp_o[1];
  assign xbar_core_data_resp[2][0] = mux_core_data_resp_o[2];

  lockstep_reg #(
      .NHARTS (NHARTS),
      .NCYCLES(NCYCLES)
  ) lockstep_reg_i (
      .clk_i,
      .rst_ni,
      .core_instr_req_i (mux_core_instr_req_i),
      .core_instr_req_o (mux_core_instr_req_o),
      .core_instr_resp_i(mux_core_instr_resp_i),
      .core_instr_resp_o(mux_core_instr_resp_o),

      .core_data_req_i (mux_core_data_req_i),
      .core_data_req_o (mux_core_data_req_o),
      .core_data_resp_i(mux_core_data_resp_i),
      .core_data_resp_o(mux_core_data_resp_o),

      .enable_i(delayed_s & dual_mode_s),
      .mask(dmr_config_s),
      .intr_i(mux_intr_i),
      .intr_o(mux_intr_o),
      .debug_i(mux_debug_req_i),
      .debug_o(mux_debug_req_o)

  );

  /************************Isolate BUS***************************/

  for (genvar i = 0; i < NHARTS; i++) begin : isolate_obi_bus_instr
    logic [NHARTS-1:0] isolate_valid_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        isolate_valid_q[i] <= '0;
      end else begin
        isolate_valid_q[i] <= isolate_core_instr_resp[i].gnt;
      end
    end
    assign isolate_core_instr_resp[i].gnt = mux_core_instr_req_o[i].req;
    assign isolate_core_instr_resp[i].rvalid = isolate_valid_q[i];
    assign isolate_core_instr_resp[i].rdata = 32'h10500073;  //wfi instruction
  end

  for (genvar i = 0; i < NHARTS; i++) begin : isolate_obi_bus_data
    logic [NHARTS-1:0] isolate_valid_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        isolate_valid_q[i] <= '0;
      end else begin
        isolate_valid_q[i] <= isolate_core_data_resp[i].gnt;
      end
    end
    assign isolate_core_data_resp[i].gnt = mux_core_data_req_o[i].req;
    assign isolate_core_data_resp[i].rvalid = isolate_valid_q[i];
    assign isolate_core_data_resp[i].rdata = 32'h0;  //0 data val
  end

  /*********************************************************/
  //*********************Safety Voter***********************//
  // Todo: Temporal solution
  // Gated outpout to avoid changing master until switch to single mode
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (~rst_ni) begin
      master_core_ff_s <= '0;
    end else begin
      if (sleep_s == 3'b111) master_core_ff_s <= master_core_s;
    end
  end

  tmr_voter #() tmr_voter0_i (
      // Instruction Bus
      .core_instr_req_i(mux_core_instr_req_o),
      .voted_core_instr_req_o(voted_core_instr_req_o[0]),
      .enable_i(tmr_voter_enable_s && master_core_ff_s[0]),
      // Data Bus
      .core_data_req_i(mux_core_data_req_o),
      .voted_core_data_req_o(voted_core_data_req_o[0]),

      .error_o(tmr_error_s[0]),
      .error_id_o(tmr_errorid_s[0])
  );
  tmr_voter #() tmr_voter1_i (
      // Instruction Bus
      .core_instr_req_i(mux_core_instr_req_o),
      .voted_core_instr_req_o(voted_core_instr_req_o[1]),
      .enable_i(tmr_voter_enable_s && master_core_ff_s[1]),
      // Data Bus
      .core_data_req_i(mux_core_data_req_o),
      .voted_core_data_req_o(voted_core_data_req_o[1]),

      .error_o(tmr_error_s[1]),
      .error_id_o(tmr_errorid_s[1])
  );
  tmr_voter #() tmr_voter2_i (
      // Instruction Bus
      .core_instr_req_i(mux_core_instr_req_o),
      .voted_core_instr_req_o(voted_core_instr_req_o[2]),
      .enable_i(tmr_voter_enable_s && master_core_ff_s[2]),
      // Data Bus
      .core_data_req_i(mux_core_data_req_o),
      .voted_core_data_req_o(voted_core_data_req_o[2]),

      .error_o(tmr_error_s[2]),
      .error_id_o(tmr_errorid_s[2])
  );

  //******************Safety Comparator********************//
  obi_req_t [NHARTS-1:0][1:0] dmr_core_instr_req_i;
  obi_req_t [NHARTS-1:0][1:0] dmr_core_data_req_i;
  for (genvar i = 0; i < NRCOMPARATORS; i++) begin : eros_dmr_comparator

    dmr_comparator #() dmr_comparator_i (
        .core_instr_req_i(dmr_core_instr_req_i[i]),
        .compared_core_instr_req_o(compared_core_instr_req_o[i]),
        .core_data_req_i(dmr_core_data_req_i[i]),
        .compared_core_data_req_o(compared_core_data_req_o[i]),
        .error_o(dmr_error_s[i])
    );
  end

  always_comb begin  //Mux Comparador 0
    dmr_core_instr_req_i[0][0] = mux_core_instr_req_o[0];
    dmr_core_data_req_i[0][0]  = mux_core_data_req_o[0];
    if (dmr_config_s == 3'b011) begin
      dmr_core_instr_req_i[0][1] = mux_core_instr_req_o[1];
      dmr_core_data_req_i[0][1]  = mux_core_data_req_o[1];
    end else if (dmr_config_s == 3'b101) begin
      dmr_core_instr_req_i[0][1] = mux_core_instr_req_o[2];
      dmr_core_data_req_i[0][1]  = mux_core_data_req_o[2];
    end else begin
      dmr_core_instr_req_i[0][1] = mux_core_instr_req_o[1];
      dmr_core_data_req_i[0][1]  = mux_core_data_req_o[1];
    end
  end
  always_comb begin  //Mux Comparador 1
    dmr_core_instr_req_i[1][0] = mux_core_instr_req_o[1];
    dmr_core_data_req_i[1][0]  = mux_core_data_req_o[1];
    if (dmr_config_s == 3'b011) begin
      dmr_core_instr_req_i[1][1] = mux_core_instr_req_o[0];
      dmr_core_data_req_i[1][1]  = mux_core_data_req_o[0];
    end else if (dmr_config_s == 3'b110) begin
      dmr_core_instr_req_i[1][1] = mux_core_instr_req_o[2];
      dmr_core_data_req_i[1][1]  = mux_core_data_req_o[2];
    end else begin
      dmr_core_instr_req_i[1][1] = mux_core_instr_req_o[0];
      dmr_core_data_req_i[1][1]  = mux_core_data_req_o[0];
    end
  end
  always_comb begin  //Mux Comparador 2   
    dmr_core_instr_req_i[2][0] = mux_core_instr_req_o[2];
    dmr_core_data_req_i[2][0]  = mux_core_data_req_o[2];
    if (dmr_config_s == 3'b110) begin
      dmr_core_instr_req_i[2][1] = mux_core_instr_req_o[1];
      dmr_core_data_req_i[2][1]  = mux_core_data_req_o[1];
    end else if (dmr_config_s == 3'b101) begin
      dmr_core_instr_req_i[2][1] = mux_core_instr_req_o[0];
      dmr_core_data_req_i[2][1]  = mux_core_data_req_o[0];
    end else begin
      dmr_core_instr_req_i[2][1] = mux_core_instr_req_o[0];
      dmr_core_data_req_i[2][1]  = mux_core_data_req_o[0];
    end
  end

  //*******************************************************//

  //***Private CPU Register***//

  for (genvar i = 0; i < NHARTS; i++) begin : priv_reg
    // ARCHITECTURE
    // ------------
    //                ,---- SLAVE[0] (System Bus)
    // CPUx <--> XBARx 
    //                `---- SLAVE[1] (Private Register)
    //

    //***CPU xbar***//
    xbar_varlat_one_to_n #(
        .XBAR_NSLAVE  (cei_mochila_pkg::CPU_XBAR_SLAVE),
        .NUM_RULES    (cei_mochila_pkg::CPU_XBAR_NRULES),
        .AGGREGATE_GNT(32'd1)                              // Not previous aggregate masters
    ) xbar_varlat_one_to_n_i (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .addr_map_i(cei_mochila_pkg::CPU_XBAR_ADDR_RULES),
        .default_idx_i(1'b0),                   //in case of not known decoded address it's forwarded down to system bus
        .master_req_i(core_data_req[i]),
        .master_resp_o(core_data_resp[i]),
        .slave_req_o(xbar_core_data_req[i]),
        .slave_resp_i(xbar_core_data_resp[i])
    );

    //***OBI Slave[1] -> Private Address CPU Register***//
    periph_to_reg #(
        .req_t(reg_pkg::reg_req_t),
        .rsp_t(reg_pkg::reg_rsp_t),
        .IW(1)
    ) cpu_periph_to_reg_i (
        .clk_i,
        .rst_ni,
        .req_i(xbar_core_data_req[i][1].req),
        .add_i(xbar_core_data_req[i][1].addr),
        .wen_i(~xbar_core_data_req[i][1].we),
        .wdata_i(xbar_core_data_req[i][1].wdata),
        .be_i(xbar_core_data_req[i][1].be),
        .id_i('0),
        .gnt_o(xbar_core_data_resp[i][1].gnt),
        .r_rdata_o(xbar_core_data_resp[i][1].rdata),
        .r_opc_o(),
        .r_id_o(),
        .r_valid_o(xbar_core_data_resp[i][1].rvalid),
        .reg_req_o(cpu_reg_req[i]),
        .reg_rsp_i(cpu_reg_rsp[i])
    );

    //***CPU Private Register***//

    cpu_private_reg #(
        .reg_req_t(reg_pkg::reg_req_t),
        .reg_rsp_t(reg_pkg::reg_rsp_t)
    ) cpu_private_reg_i (
        .clk_i,
        .rst_ni,

        // Bus Interface
        .reg_req_i(cpu_reg_req[i]),
        .reg_rsp_o(cpu_reg_rsp[i]),

        .Core_id_i(Core_ID[i]),
        .Hart_intc_ack_o(Hart_intc_ack_s[i])
    );
  end
endmodule
