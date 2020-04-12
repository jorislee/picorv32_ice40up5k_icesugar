# ---- iCE40 UltraPlus icesugar  Board ----

icebsim: icesugar_tb.vvp icesugar_fw.hex
	vvp -N $< +firmware=icesugar_fw.hex

icebsynsim: icesugar_syn_tb.vvp icesugar_fw.hex
	vvp -N $< +firmware=icesugar_fw.hex

icesugar.json: hdl/icesugar.v hdl/ice40up5k_spram.v hdl/spimemio.v hdl/simpleuart.v hdl/picosoc.v picorv32/picorv32.v
	yosys -ql icesugar.log -p 'synth_ice40 -top icesugar -json icesugar.json' $^

icesugar_tb.vvp: hdl/icesugar_tb.v hdl/icesugar.v hdl/ice40up5k_spram.v hdl/spimemio.v hdl/simpleuart.v hdl/picosoc.v picorv32/picorv32.v hdl/spiflash.v
	iverilog -s testbench -o $@ $^ `yosys-config --datdir/ice40/cells_sim.v`

icesugar_syn_tb.vvp: hdl/icesugar_tb.v hdl/icesugar_syn.v hdl/spiflash.v
	iverilog -s testbench -o $@ $^ `yosys-config --datdir/ice40/cells_sim.v`

icesugar_syn.v: icesugar.json
	yosys -p 'read_json icesugar.json; write_verilog icesugar_syn.v'

icesugar.asc: constr/icesugar.pcf icesugar.json
	nextpnr-ice40 --freq 13 --up5k --asc icesugar.asc --pcf constr/icesugar.pcf --json icesugar.json

icesugar.bin: icesugar.asc
	icetime -d up5k -c 12 -mtr icesugar.rpt icesugar.asc
	icepack icesugar.asc icesugar.bin

UNAME_S := $(shell uname -s)
icesprog_sys: 
ifeq ($(UNAME_S),Darwin)
    PROG = ./tools/macos/icesprog
endif
ifeq ($(UNAME_S),Linux)
    PROG = ./tools/linux/icesprog
endif

icesprog: icesugar.bin icesugar_fw.bin
	@echo  "icesprog"
	$(PROG) icesugar.bin
	$(PROG) -o 0x100000 icesugar_fw.bin
	@#truncate -s 1048576 icesugar.bin
	@#@cat icesugar.bin icesugar_fw.bin > icesugar_spiflash.bin
	@#if [ -d '$(ICELINK_DIR)' ]; \
        #then \
            #cp icesugar.bin $(ICELINK_DIR); \
        #else \
            #echo "iCELink not found"; \
            #exit 1; \
    #fi

icebprog_fw: icesugar_fw.bin
	iceprog -o 1M icesugar_fw.bin

icesugar_sections.lds: ./hdl/sections.lds
	riscv32-unknown-elf-cpp -P -DICEBREAKER -o $@ $^

icesugar_fw.elf: ./src/icesugar_sections.lds ./src/start.s ./src/firmware.c
	riscv32-unknown-elf-gcc -DICEBREAKER -march=rv32ic -Wl,-Bstatic,-T,./src/icesugar_sections.lds,--strip-debug -ffreestanding -nostdlib -o icesugar_fw.elf ./src/start.s ./src/firmware.c

icesugar_fw.hex: icesugar_fw.elf
	riscv32-unknown-elf-objcopy -O verilog icesugar_fw.elf icesugar_fw.hex

icesugar_fw.bin: icesugar_fw.elf
	riscv32-unknown-elf-objcopy -O binary icesugar_fw.elf icesugar_fw.bin

# ---- Testbench for SPI Flash Model ----

spiflash_tb: spiflash_tb.vvp firmware.hex
	vvp -N $<

spiflash_tb.vvp: spiflash.v spiflash_tb.v
	iverilog -s testbench -o $@ $^

# ---- ASIC Synthesis Tests ----

cmos.log: spimemio.v simpleuart.v picosoc.v ../picorv32.v
	yosys -l cmos.log -p 'synth -top picosoc; abc -g cmos2; opt -fast; stat' $^

# ---- Clean ----

clean:
	rm -f testbench.vvp testbench.vcd spiflash_tb.vvp spiflash_tb.vcd
	rm -f icesugar_fw.elf icesugar_fw.hex icesugar_fw.bin
	rm -f icesugar.json icesugar.log icesugar.asc icesugar.rpt icesugar.bin
	rm -f icesugar_syn.v icesugar_syn_tb.vvp icesugar_tb.vvp

.PHONY: spiflash_tb clean
.PHONY: icebprog icebprog_fw icebsim icebsynsim
