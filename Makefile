#---------------------------------------------------------------------
# Makefile for BSGS (GPU/CPU)
#
# Author : Jean-Luc PONS
# Modernized for CUDA 13 and auto-detected GPU arch
#---------------------------------------------------------------------

# ===== Sources / Objects =====
ifdef gpu
SRC = SECPK1/IntGroup.cpp main.cpp SECPK1/Random.cpp \
      Timer.cpp SECPK1/Int.cpp SECPK1/IntMod.cpp \
      SECPK1/Point.cpp SECPK1/SECP256K1.cpp \
      GPU/GPUEngine.cu Kangaroo.cpp HashTable.cpp \
      Backup.cpp Thread.cpp Check.cpp Network.cpp Merge.cpp PartMerge.cpp

OBJDIR = obj

OBJET = $(addprefix $(OBJDIR)/, \
      SECPK1/IntGroup.o main.o SECPK1/Random.o \
      Timer.o SECPK1/Int.o SECPK1/IntMod.o \
      SECPK1/Point.o SECPK1/SECP256K1.o \
      GPU/GPUEngine.o Kangaroo.o HashTable.o Thread.o \
      Backup.o Check.o Network.o Merge.o PartMerge.o)
else
SRC = SECPK1/IntGroup.cpp main.cpp SECPK1/Random.cpp \
      Timer.cpp SECPK1/Int.cpp SECPK1/IntMod.cpp \
      SECPK1/Point.cpp SECPK1/SECP256K1.cpp \
      Kangaroo.cpp HashTable.cpp Thread.cpp Check.cpp \
      Backup.cpp Network.cpp Merge.cpp PartMerge.cpp

OBJDIR = obj

OBJET = $(addprefix $(OBJDIR)/, \
      SECPK1/IntGroup.o main.o SECPK1/Random.o \
      Timer.o SECPK1/Int.o SECPK1/IntMod.o \
      SECPK1/Point.o SECPK1/SECP256K1.o \
      Kangaroo.o HashTable.o Thread.o Check.o Backup.o \
      Network.o Merge.o PartMerge.o)
endif

# ===== Toolchain autodetect =====
CXX       ?= g++

# Prefer CUDA 13 if present, else use /usr/local/cuda
CUDA      ?= $(firstword $(wildcard /usr/local/cuda-13* /usr/local/cuda))
NVCC      := $(CUDA)/bin/nvcc

# Host compiler for NVCC: try g++-12, then g++-11, then system g++
CXXCUDA   ?= $(shell which g++-12 2>/dev/null || which g++-11 2>/dev/null || which g++)

# Compute capability auto-detect (e.g., "9.0" -> "90")
# Falls back to 90 if detection fails (Hopper SM_90; will still build & run)
CCAP      ?= $(shell nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -n1 | tr -d '. ' | tr -d ' ')
ifeq ($(strip $(CCAP)),)
  CCAP := 90
endif

# Emit both SASS and PTX for forward-compat
GENCODE   := -gencode=arch=compute_$(CCAP),code=sm_$(CCAP) \
             -gencode=arch=compute_$(CCAP),code=compute_$(CCAP)

# ===== Flags =====
# Add -allow-unsupported-compiler to survive newer host compilers with older CUDA toolkits.
COMMON_WARN := -Wno-unused-result -Wno-write-strings
COMMON_INC  := -I. -I$(CUDA)/include

ifdef gpu
  ifdef debug
    CXXFLAGS = -DWITHGPU -m64 -mssse3 $(COMMON_WARN) -g $(COMMON_INC)
  else
    CXXFLAGS = -DWITHGPU -m64 -mssse3 $(COMMON_WARN) -O2 $(COMMON_INC)
  endif
  LFLAGS   = -lpthread -L$(CUDA)/lib64 -lcudart
else
  ifdef debug
    CXXFLAGS = -m64 -mssse3 $(COMMON_WARN) -g $(COMMON_INC)
  else
    CXXFLAGS = -m64 -mssse3 $(COMMON_WARN) -O2 $(COMMON_INC)
  endif
  LFLAGS   = -lpthread
endif

# ===== Rules =====
$(OBJDIR)/%.o : %.cpp
	$(CXX) $(CXXFLAGS) -o $@ -c $<

ifdef gpu
# Build GPUEngine.cu with SASS+PTX and auto CC
ifdef debug
$(OBJDIR)/GPU/GPUEngine.o: GPU/GPUEngine.cu
	$(NVCC) -G -maxrregcount=0 --ptxas-options=-v --compile \
		--compiler-options -fPIC -ccbin $(CXXCUDA) -m64 -g \
		$(COMMON_INC) $(GENCODE) -allow-unsupported-compiler \
		-o $@ -c $<
else
$(OBJDIR)/GPU/GPUEngine.o: GPU/GPUEngine.cu
	$(NVCC) -maxrregcount=0 --ptxas-options=-v --compile \
		--compiler-options -fPIC -ccbin $(CXXCUDA) -m64 -O2 \
		$(COMMON_INC) $(GENCODE) -allow-unsupported-compiler \
		-o $@ -c $<
endif
endif

all: bsgs

bsgs: $(OBJET)
	@echo Making Kangaroo...
	$(CXX) $(OBJET) $(LFLAGS) -o kangaroo

$(OBJET): | $(OBJDIR) $(OBJDIR)/SECPK1 $(OBJDIR)/GPU

$(OBJDIR):
	mkdir -p $(OBJDIR)

$(OBJDIR)/GPU: $(OBJDIR)
	mkdir -p $(OBJDIR)/GPU

$(OBJDIR)/SECPK1: $(OBJDIR)
	mkdir -p $(OBJDIR)/SECPK1

clean:
	@echo Cleaning...
	@rm -f obj/*.o
	@rm -f obj/GPU/*.o
	@rm -f obj/SECPK1/*.o
	@rm -f kangaroo
