# Product Context

## Project Overview
The Expert Advisor (EA) system is designed to operate in a normal mode environment, focusing on robust trading logic, risk management, and predictable loss control. The EA is intended to lose money in a structured, predictable way, with the goal of using a trade copier to reverse its trades and turn the losses into profit.

## Objectives
- Develop an EA with solid trading logic, risk management, and predictable loss control.
- Ensure the EA can be thoroughly tested in a simulated environment.
- Implement a modular architecture to support scalability and maintainability.
- Leverage the Follow-the-Sun (FTS) methodology for continuous development and rapid feedback cycles.

## Key Features
- Modular architecture with independent modules for configuration, market data processing, trading logic, risk management, order execution, logging/monitoring, and testing.
- Predictable loss generation criteria, including loss consistency targets, stop-loss execution rates, and tracking of accidental wins.
- Detailed tracking and mitigation of accidental wins to refine the trading logic.
- Comprehensive testing and simulation capabilities to ensure the EA performs consistently under live and simulated market conditions.
